import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { createHmac } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWTVerifyGetKey } from 'jose';
import { AuthStore } from './auth';
import { TelegramAuth, validateTelegramInitData } from './telegramAuth';
import { createOnlineServer } from './app';

const botToken = '8834741855:isolated-test-secret';
function initData(id = 123456789, username?: string, time = Math.floor(Date.now() / 1000)) {
  const data = new URLSearchParams({
    auth_date: String(time),
    query_id: 'test-query',
    user: JSON.stringify({ id, first_name: 'Игрок', ...(username ? { username } : {}) }),
  });
  const check = [...data]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');
  data.set(
    'hash',
    createHmac('sha256', createHmac('sha256', 'WebAppData').update(botToken).digest())
      .update(check)
      .digest('hex'),
  );
  return data.toString();
}
let privateKey: Awaited<ReturnType<typeof generateKeyPair>>['privateKey'];
let keys: JWTVerifyGetKey;
beforeAll(async () => {
  const pair = await generateKeyPair('RS256');
  privateKey = pair.privateKey;
  keys = createLocalJWKSet({
    keys: [{ ...(await exportJWK(pair.publicKey)), kid: 'test', alg: 'RS256' }],
  });
});
function jwt(nonce: string, values: Record<string, unknown> = {}) {
  return new SignJWT({ id: 123456789, preferred_username: 'TelegramPlayer', nonce, ...values })
    .setProtectedHeader({ alg: 'RS256', kid: 'test' })
    .setIssuer('https://oauth.telegram.org')
    .setAudience('8834741855')
    .setSubject('different-oidc-subject')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(privateKey);
}
const dirs: string[] = [];
const servers: ReturnType<typeof createOnlineServer>[] = [];
afterEach(async () => {
  await Promise.all(servers.splice(0).map((server) => server.close()));
  await Promise.all(dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

describe('Telegram identity verification', () => {
  it('checks raw Mini App signatures and safe 52-bit IDs without trusting a display name', () => {
    expect(validateTelegramInitData(initData(123456789, 'TelegramPlayer'), botToken)).toEqual({
      id: '123456789',
      username: 'TelegramPlayer',
    });
    expect(validateTelegramInitData(initData(4503599627370495), botToken)).toEqual({
      id: '4503599627370495',
    });
    expect(() =>
      validateTelegramInitData(initData().replace('123456789', '123456788'), botToken),
    ).toThrow('Подпись');
    expect(() => validateTelegramInitData(initData(), 'wrong-secret')).toThrow('Подпись');
    expect(() => validateTelegramInitData(`${initData()}&auth_date=1`, botToken)).toThrow();
    expect(() => validateTelegramInitData(initData(0), botToken)).toThrow('профиль');
  });
  it('rejects old and future Mini App credentials', () => {
    const now = Math.floor(Date.now() / 1000);
    expect(() => validateTelegramInitData(initData(1, undefined, now - 301), botToken)).toThrow(
      'устарели',
    );
    expect(() => validateTelegramInitData(initData(1, undefined, now + 40), botToken)).toThrow(
      'устарели',
    );
  });
  it('binds OIDC signatures to the browser, audience and single-use nonce', async () => {
    const auth = new TelegramAuth({ clientId: '8834741855', keys });
    const challenge = auth.begin('login', null);
    const idToken = await jwt(challenge.nonce);
    const cookie = auth.cookie(challenge.token, true);
    expect(cookie).toContain('HttpOnly; SameSite=Strict; Secure;');
    await expect(auth.complete(cookie, { nonce: challenge.nonce, idToken }, null)).resolves.toEqual(
      { user: { id: '123456789', username: 'TelegramPlayer' }, linkOwner: null },
    );
    await expect(auth.complete(cookie, { nonce: challenge.nonce, idToken }, null)).rejects.toThrow(
      'истёк',
    );
    const wrong = auth.begin('login', null);
    await expect(
      auth.complete(auth.cookie(wrong.token, false), { nonce: wrong.nonce, idToken }, null),
    ).rejects.toThrow('подтвердить');
    const missing = auth.begin('login', null);
    await expect(
      auth.complete(undefined, { nonce: missing.nonce, idToken: await jwt(missing.nonce) }, null),
    ).rejects.toThrow('истёк');
  });
  it('rejects invalid OIDC claims and signatures', async () => {
    for (const claims of [
      { iss: 'https://attacker.test' },
      { aud: 'another-client' },
      { exp: 1 },
      { iat: 1 },
      { id: 0 },
    ]) {
      const auth = new TelegramAuth({ clientId: '8834741855', keys });
      const challenge = auth.begin('login', null);
      // Claims are applied after the ordinary defaults for issuer/audience/time.
      const token = await new SignJWT({
        id: 123456789,
        sub: 'test',
        nonce: challenge.nonce,
        iss: 'https://oauth.telegram.org',
        aud: '8834741855',
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 300,
        ...claims,
      })
        .setProtectedHeader({ alg: 'RS256', kid: 'test' })
        .sign(privateKey);
      await expect(
        auth.complete(
          auth.cookie(challenge.token, false),
          { nonce: challenge.nonce, idToken: token },
          null,
        ),
      ).rejects.toThrow('подтвердить');
    }
    const auth = new TelegramAuth({ clientId: '8834741855', keys });
    const challenge = auth.begin('login', null);
    const token = await jwt(challenge.nonce);
    await expect(
      auth.complete(
        auth.cookie(challenge.token, false),
        { nonce: challenge.nonce, idToken: token.slice(0, -10) + 'xxxxxxxxxx' },
        null,
      ),
    ).rejects.toThrow('подтвердить');
  });
  it('refuses link attempts for guests or after the account changed', async () => {
    const auth = new TelegramAuth({ botToken });
    expect(() => auth.begin('link', null)).toThrow('Сначала');
    const challenge = auth.begin('link', 'ExistingPlayer');
    await expect(
      auth.complete(
        auth.cookie(challenge.token, false),
        { nonce: challenge.nonce, initData: initData() },
        'OtherPlayer',
      ),
    ).rejects.toThrow('изменился');
  });
});

describe('Telegram accounts', () => {
  it('creates an account without email/password and preserves identity after nickname changes and restart', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-telegram-'));
    dirs.push(dir);
    const path = join(dir, 'accounts.json');
    const auth = new AuthStore(path);
    const created = await auth.telegramLogin({ id: '123456789', username: 'TelegramPlayer' });
    const profile = auth.profile(`four_session=${created.token}`);
    expect(profile).toMatchObject({
      username: 'TelegramPlayer',
      email: null,
      hasPassword: false,
      telegramLinked: true,
    });
    expect(auth.leaderboardUsernames()).toEqual(['TelegramPlayer']);
    await auth.adminUpdate('TelegramPlayer', { username: 'GamePlayer' });
    const reopened = new AuthStore(path);
    const next = await reopened.telegramLogin({ id: '123456789', username: 'NewTelegramHandle' });
    expect(next.username).toBe('GamePlayer');
    expect(reopened.adminAccounts()).toHaveLength(1);
    await expect(reopened.login('GamePlayer', 'wrong-password')).rejects.toThrow('Неверное');
  });
  it('never takes over a password account with the same nickname', async () => {
    const auth = new AuthStore(null);
    await auth.register('TelegramPlayer', 'password-123');
    const created = await auth.telegramLogin({ id: '123456789', username: 'TelegramPlayer' });
    expect(created.username).toBe('tg_123456789');
    expect((await auth.login('TelegramPlayer', 'password-123')).username).toBe('TelegramPlayer');
    expect(auth.adminAccounts()).toHaveLength(2);
  });
  it('links an existing account, protects uniqueness, and respects blocking', async () => {
    const auth = new AuthStore(null);
    await auth.register('ExistingPlayer', 'password-123');
    await auth.register('OtherPlayer', 'password-123');
    const linked = await auth.telegramLogin({ id: '123456789' }, 'ExistingPlayer');
    expect(linked.username).toBe('ExistingPlayer');
    expect(auth.profile(`four_session=${linked.token}`)?.hasPassword).toBe(true);
    expect((await auth.telegramLogin({ id: '123456789', username: 'Whatever' })).username).toBe(
      'ExistingPlayer',
    );
    await expect(auth.telegramLogin({ id: '123456789' }, 'OtherPlayer')).rejects.toThrow('другому');
    await expect(auth.telegramLogin({ id: '987654321' }, 'ExistingPlayer')).rejects.toThrow(
      'другой',
    );
    await auth.adminUpdate('ExistingPlayer', { disabled: true });
    await expect(auth.telegramLogin({ id: '123456789' })).rejects.toThrow('заблокирован');
    await auth.adminDelete('ExistingPlayer');
    expect((await auth.telegramLogin({ id: '123456789' })).username).toBe('tg_123456789');
  });
  it('allows a Telegram-only player to create a password and then requires it for changes', async () => {
    const auth = new AuthStore(null);
    const created = await auth.telegramLogin({ id: '123456789' });
    const changed = await auth.changePassword(
      `four_session=${created.token}`,
      '',
      'new-password-123',
    );
    expect(auth.profile(`four_session=${created.token}`)).toBeNull();
    expect(auth.profile(`four_session=${changed.token}`)).toMatchObject({
      hasPassword: true,
      telegramLinked: true,
    });
    expect((await auth.login(created.username, 'new-password-123')).username).toBe(
      created.username,
    );
    await expect(
      auth.changePassword(`four_session=${changed.token}`, '', 'another-password'),
    ).rejects.toThrow('неверен');
  });
});

describe('Telegram HTTP sessions', () => {
  it('creates a normal cookie session, exposes server statistics and rejects replay and cross-site login', async () => {
    const server = createOnlineServer({
      authFile: null,
      statsFile: null,
      staticDir: null,
      mailer: null,
      telegram: { botToken, clientId: '8834741855', keys },
    });
    servers.push(server);
    await new Promise<void>((resolve) => server.httpServer.listen(0, '127.0.0.1', resolve));
    const url = `http://127.0.0.1:${(server.httpServer.address() as AddressInfo).port}`;
    const post = (path: string, body: object, cookie = '', headers = {}) =>
      fetch(url + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Cookie: cookie, ...headers },
        body: JSON.stringify(body),
      });
    expect(await fetch(url + '/auth/telegram/config').then((r) => r.json())).toEqual({
      clientId: '8834741855',
      miniApp: true,
    });
    expect(
      (
        await post('/auth/telegram/begin', { purpose: 'login' }, '', {
          Origin: 'https://attacker.test',
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await post('/auth/telegram/begin', { purpose: 'login' }, '', {
          'Sec-Fetch-Site': 'cross-site',
        })
      ).status,
    ).toBe(403);
    const begin = await post('/auth/telegram/begin', { purpose: 'login' });
    const challenge = (await begin.json()) as { nonce: string };
    const cookie = begin.headers.getSetCookie()[0].split(';')[0];
    const body = { nonce: challenge.nonce, initData: initData(123456789, 'HttpTelegram') };
    const complete = await post('/auth/telegram/complete', body, cookie);
    expect(complete.status).toBe(200);
    expect(await complete.json()).toMatchObject({
      username: 'HttpTelegram',
      telegramLinked: true,
      hasPassword: false,
    });
    const session = complete.headers
      .getSetCookie()
      .find((cookie) => cookie.startsWith('four_session='))!
      .split(';')[0];
    expect(
      await fetch(url + '/auth/me', { headers: { Cookie: session } }).then((r) => r.json()),
    ).toMatchObject({ username: 'HttpTelegram' });
    expect((await fetch(url + '/auth/history', { headers: { Cookie: session } })).status).toBe(200);
    expect((await post('/auth/telegram/complete', body, cookie)).status).toBe(401);
    const oidcBegin = await post('/auth/telegram/begin', { purpose: 'login' });
    const oidc = (await oidcBegin.json()) as { nonce: string };
    const oidcResult = await post(
      '/auth/telegram/complete',
      { nonce: oidc.nonce, idToken: await jwt(oidc.nonce) },
      oidcBegin.headers.getSetCookie()[0].split(';')[0],
    );
    expect(await oidcResult.json()).toMatchObject({ username: 'HttpTelegram' });
  });
});
