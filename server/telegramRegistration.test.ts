import { afterEach, describe, expect, it, vi } from 'vitest';
import { createHmac } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { AuthStore } from './auth.ts';
import { TelegramAuth } from './telegramAuth.ts';
import { createOnlineServer } from './app.ts';
import type { MailMessage } from './email.ts';

const botToken = '8834741855:registration-test-only';
const servers: ReturnType<typeof createOnlineServer>[] = [];
afterEach(async () => {
  vi.restoreAllMocks();
  await Promise.all(servers.splice(0).map((s) => s.close()));
});

function signed(id: number, username?: string) {
  const values = new URLSearchParams({
    auth_date: String(Math.floor(Date.now() / 1000)),
    user: JSON.stringify({ id, username }),
  });
  const data = [...values]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join('\n');
  values.set(
    'hash',
    createHmac('sha256', createHmac('sha256', 'WebAppData').update(botToken).digest())
      .update(data)
      .digest('hex'),
  );
  return values.toString();
}
async function setup() {
  const emails: MailMessage[] = [];
  const server = createOnlineServer({
    authFile: null,
    statsFile: null,
    staticDir: null,
    telegram: { botToken },
    mailer: {
      sendVerification: async (m) => {
        emails.push(m);
      },
      sendPasswordReset: async (m) => {
        emails.push(m);
      },
    },
  });
  servers.push(server);
  await new Promise<void>((r) => server.httpServer.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${(server.httpServer.address() as AddressInfo).port}`;
  const post = (path: string, body: object, cookie = '', extra: Record<string, string> = {}) =>
    fetch(url + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Cookie: cookie, ...extra },
      body: JSON.stringify(body),
    });
  const cookie = (r: Response, name = 'four_telegram_login') =>
    r.headers
      .getSetCookie()
      .find((v) => v.startsWith(`${name}=`))!
      .split(';')[0];
  const begin = async (id: number, name?: string) => {
    const start = await post('/auth/telegram/begin', { purpose: 'login' });
    const { nonce } = (await start.json()) as { nonce: string };
    const response = await post(
      '/auth/telegram/complete',
      { nonce, initData: signed(id, name) },
      cookie(start),
    );
    return response;
  };
  return { url, emails, post, cookie, begin };
}

describe('explicit Telegram registration', () => {
  it('does not create an account before choosing a unique nickname; rejects forged, missing and replayed proof', async () => {
    const { url, post, begin, cookie } = await setup();
    await post('/auth/register', {
      username: 'Occupied',
      password: 'password-123',
      email: 'old@example.org',
    });
    const pending = await begin(101010101, 'Occupied');
    expect(await pending.json()).toEqual({
      registrationRequired: true,
      suggestedUsername: 'Occupied',
    });
    expect(await fetch(url + '/auth/me').then((r) => r.json())).toMatchObject({
      authenticated: false,
    });
    expect(
      (await post('/auth/telegram/register', { username: 'NewName', id: '101010101' })).status,
    ).toBe(401);
    const proof = cookie(pending);
    expect((await post('/auth/telegram/register', { username: 'occupied' }, proof)).status).toBe(
      409,
    );
    expect((await post('/auth/telegram/register', { username: 'Русский' }, proof)).status).toBe(
      400,
    );
    const registered = await post(
      '/auth/telegram/register',
      { username: 'SelectedName', id: '999999999' },
      proof,
    );
    expect(await registered.json()).toMatchObject({
      username: 'SelectedName',
      email: null,
      hasPassword: false,
    });
    expect((await post('/auth/telegram/register', { username: 'OtherName' }, proof)).status).toBe(
      401,
    );
    expect(await (await begin(101010101, 'ChangedHandle')).json()).toMatchObject({
      username: 'SelectedName',
    });
    expect(await (await begin(999999999)).json()).toMatchObject({
      registrationRequired: true,
      suggestedUsername: '999999999',
    });
  });

  it('expires, cancels and binds pending registrations to the initiating account', async () => {
    const telegram = new TelegramAuth({ botToken });
    const pending = telegram.registration({ id: '123456789' }, null);
    const proof = telegram.cookie(pending.token, false);
    expect(() => telegram.pending(proof, 'OtherAccount')).toThrow('изменился');
    telegram.pending(proof, null).finish();
    expect(() => telegram.pending(proof, null)).toThrow('истёк');
    const expiring = telegram.registration({ id: '987654321' }, null);
    const now = Date.now();
    vi.spyOn(Date, 'now').mockReturnValue(now + 10 * 60_000 + 1);
    expect(() => telegram.pending(telegram.cookie(expiring.token, false), null)).toThrow('истёк');
    vi.restoreAllMocks();
    const { post, begin, cookie } = await setup();
    const response = await begin(123456789);
    const cancelled = cookie(response);
    expect((await post('/auth/telegram/cancel', {}, cancelled)).status).toBe(200);
    expect(
      (await post('/auth/telegram/register', { username: 'Cancelled' }, cancelled)).status,
    ).toBe(401);
  });
});

describe('Telegram recovery and email binding', () => {
  it('verifies email before binding, protects uniqueness and ownership, and revokes Telegram reset links', async () => {
    const { emails, post, begin, cookie, url } = await setup();
    const pending = await begin(101010101, 'TestPlayer');
    const response = await post(
      '/auth/telegram/register',
      { username: 'TestPlayer' },
      cookie(pending),
    );
    const session = cookie(response, 'four_session');
    expect((await post('/auth/email/bind', { email: 'mine@example.org' })).status).toBe(401);
    expect((await post('/auth/email/bind', { email: 'mine@example.org' }, session)).status).toBe(
      200,
    );
    expect(emails[0]).toMatchObject({
      username: 'TestPlayer',
      email: 'mine@example.org',
      purpose: 'binding',
    });
    expect(
      await fetch(url + '/auth/me', { headers: { Cookie: session } }).then((r) => r.json()),
    ).toMatchObject({ email: null });
    const botHeaders = { Authorization: `Bearer ${botToken}` };
    expect((await post('/auth/telegram/bot-reset', { id: '101010101' })).status).toBe(403);
    expect(
      (
        await post('/auth/telegram/bot-reset', { id: '101010101' }, '', {
          Authorization: 'Bearer wrong',
        })
      ).status,
    ).toBe(403);
    const recovery = (await (
      await post('/auth/telegram/bot-reset', { id: '101010101' }, '', botHeaders)
    ).json()) as { token: string };
    expect(recovery.token).toMatch(/^[a-f0-9]{64}$/);
    expect(
      await (await post('/auth/telegram/bot-reset', { id: '101010101' }, '', botHeaders)).json(),
    ).toEqual(recovery);
    const verified = await post('/auth/verify', { token: emails[0].token });
    expect(verified.status).toBe(200);
    expect((await post('/auth/verify', { token: emails[0].token })).status).toBe(400);
    expect(
      (
        await post('/auth/password-reset/complete', {
          token: recovery.token,
          password: 'password-123',
        })
      ).status,
    ).toBe(400);
    expect(
      await fetch(url + '/auth/me', { headers: { Cookie: session } }).then((r) => r.json()),
    ).toMatchObject({ email: 'mine@example.org', emailVerified: true });
    expect((await post('/auth/email/bind', { email: 'another@example.org' }, session)).status).toBe(
      409,
    );
    const second = await begin(202020202);
    const created = await post(
      '/auth/telegram/register',
      { username: 'OtherPlayer' },
      cookie(second),
    );
    expect(
      (
        await post(
          '/auth/email/bind',
          { email: 'mine@example.org' },
          cookie(created, 'four_session'),
          { 'X-Real-IP': '198.51.100.2' },
        )
      ).status,
    ).toBe(409);
    expect(
      (
        await post('/auth/password-reset/request', { email: 'mine@example.org' }, '', {
          'X-Real-IP': '198.51.100.2',
        })
      ).status,
    ).toBe(200);
    expect(emails[1].username).toBe('TestPlayer');
  });

  it('uses one-time Telegram recovery, invalidates sessions and falls back to email after binding', async () => {
    const auth = new AuthStore(null);
    const created = await auth.telegramLogin({ id: '123456789' }, null, 'RecoveryPlayer');
    const pending = await auth.requestTelegramPasswordReset('123456789');
    if (!pending || !('token' in pending)) throw new Error('Missing recovery token');
    const changed = await auth.resetPassword(pending.token, 'password-123');
    expect(auth.profile(`four_session=${created.token}`)).toBeNull();
    expect((await auth.login('RecoveryPlayer', 'password-123')).username).toBe('RecoveryPlayer');
    await expect(auth.resetPassword(pending.token, 'password-456')).rejects.toThrow('устарела');
    const mail = await auth.bindEmail(`four_session=${changed.token}`, 'bound@example.org');
    await auth.verifyEmail(mail.token);
    expect(await auth.requestTelegramPasswordReset('123456789')).toEqual({ viaEmail: true });
    expect(await auth.requestTelegramPasswordReset('987654321')).toBeNull();
    await auth.adminUpdate('RecoveryPlayer', { disabled: true });
    expect(await auth.requestTelegramPasswordReset('123456789')).toBeNull();
  });

  it('rejects a mail binding race rather than moving the email from another player', async () => {
    const auth = new AuthStore(null);
    const a = await auth.telegramLogin({ id: '111111111' }, null, 'PlayerA');
    const b = await auth.telegramLogin({ id: '222222222' }, null, 'PlayerB');
    const first = await auth.bindEmail(`four_session=${a.token}`, 'race@example.org');
    const second = await auth.bindEmail(`four_session=${b.token}`, 'race@example.org');
    await auth.verifyEmail(first.token);
    await expect(auth.verifyEmail(second.token)).rejects.toThrow('уже привязан');
    expect(auth.profile(`four_session=${b.token}`)?.email).toBeNull();
  });

  it('expires bot reset links and replaces a pending email without binding the previous address', async () => {
    const auth = new AuthStore(null);
    const created = await auth.telegramLogin({ id: '111111111' }, null, 'ExpiringPlayer');
    const reset = await auth.requestTelegramPasswordReset('111111111');
    if (!reset || !('token' in reset)) throw new Error('Missing reset');
    const now = Date.now();
    vi.spyOn(Date, 'now').mockReturnValue(now + 15 * 60_000 + 1);
    await expect(auth.resetPassword(reset.token, 'password-123')).rejects.toThrow('устарела');
    vi.restoreAllMocks();
    const first = await auth.bindEmail(`four_session=${created.token}`, 'first@example.org');
    const second = await auth.bindEmail(`four_session=${created.token}`, 'second@example.org');
    await expect(auth.verifyEmail(first.token)).rejects.toThrow('устарела');
    await auth.verifyEmail(second.token);
    expect(auth.profile(`four_session=${created.token}`)?.email).toBe('second@example.org');
  });
});
