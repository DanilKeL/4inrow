import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import {
  createRemoteJWKSet,
  customFetch,
  errors,
  jwtVerify,
  type FetchImplementation,
  type JWTVerifyGetKey,
} from 'jose';
import { request } from 'node:https';
import { isIP } from 'node:net';
import { AuthError } from './auth.ts';

export interface TelegramUser {
  id: string;
  username?: string;
}
export interface TelegramAuthOptions {
  botToken?: string;
  clientId?: string;
  /** Isolated verification keys for tests; production always uses Telegram's JWKS. */
  keys?: JWTVerifyGetKey;
}
const COOKIE = 'four_telegram_login';
const AGE = 10 * 60_000;
// Reuse the server's reachable Telegram route while keeping the official TLS
// hostname, certificate validation and JWKS URL. No server addresses in source.
const route = process.env.TELEGRAM_API_ADDRESS;
if (route && isIP(route) !== 4) throw new Error('Invalid Telegram network route');
const routedFetch: FetchImplementation = (url, options) =>
  new Promise((resolve, reject) => {
    const req = request(
      url,
      {
        family: 4,
        servername: 'oauth.telegram.org',
        lookup: (_host, _options, callback) => callback(null, route!, 4),
        headers: Object.fromEntries(options.headers),
        signal: options.signal,
      },
      (response) => {
        const chunks: Buffer[] = [];
        let bytes = 0;
        response.on('data', (chunk) => {
          bytes += chunk.length;
          if (bytes > 128000) req.destroy(new Error('Telegram verification response too large'));
          else chunks.push(Buffer.from(chunk));
        });
        response.on('error', reject);
        response.on('end', () =>
          resolve(
            new Response(Buffer.concat(chunks).toString('utf8'), {
              status: response.statusCode ?? 502,
              headers: { 'Content-Type': 'application/json' },
            }),
          ),
        );
      },
    );
    req.on('error', reject);
    req.end();
  });
const keys = createRemoteJWKSet(new URL('https://oauth.telegram.org/.well-known/jwks.json'), {
  timeoutDuration: 5000,
  ...(route ? { [customFetch]: routedFetch } : {}),
});

function user(raw: unknown): TelegramUser {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw))
    throw new AuthError(401, 'Telegram не передал профиль.');
  const value = raw as Record<string, unknown>;
  const id =
    typeof value.id === 'number' && Number.isSafeInteger(value.id) ? String(value.id) : value.id;
  if (typeof id !== 'string' || !/^[1-9]\d{0,15}$/.test(id) || Number(id) > Number.MAX_SAFE_INTEGER)
    throw new AuthError(401, 'Некорректный профиль Telegram.');
  const username =
    typeof value.username === 'string' && /^[A-Za-z0-9_]{3,32}$/.test(value.username)
      ? value.username
      : undefined;
  return { id, ...(username ? { username } : {}) };
}

export function validateTelegramInitData(
  raw: unknown,
  token: string,
  now = Date.now(),
): TelegramUser {
  if (typeof raw !== 'string' || raw.length > 12000)
    throw new AuthError(400, 'Некорректные данные Telegram.');
  const data = new URLSearchParams(raw);
  const unique = new Set<string>();
  for (const [key] of data) {
    if (unique.has(key)) throw new AuthError(401, 'Некорректные данные Telegram.');
    unique.add(key);
  }
  const hash = data.get('hash');
  if (!hash || !/^[a-f0-9]{64}$/.test(hash))
    throw new AuthError(401, 'Подпись Telegram недействительна.');
  const check = [...data]
    .filter(([key]) => key !== 'hash')
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');
  const secret = createHmac('sha256', 'WebAppData').update(token).digest();
  const actual = createHmac('sha256', secret).update(check).digest();
  if (!timingSafeEqual(actual, Buffer.from(hash, 'hex')))
    throw new AuthError(401, 'Подпись Telegram недействительна.');
  const date = Number(data.get('auth_date')) * 1000;
  if (!Number.isSafeInteger(date) || date > now + 30000 || now - date > 5 * 60_000)
    throw new AuthError(401, 'Данные Telegram устарели. Откройте игру из Telegram заново.');
  try {
    return user(JSON.parse(data.get('user') ?? 'null'));
  } catch (error) {
    if (error instanceof AuthError) throw error;
    throw new AuthError(401, 'Некорректный профиль Telegram.');
  }
}

export class TelegramAuth {
  private attempts = new Map<
    string,
    { nonce: string; owner: string | null; purpose: 'login' | 'link'; expires: number }
  >();
  private botToken?: string;
  private clientId?: string;
  private keys: JWTVerifyGetKey;
  constructor(options?: TelegramAuthOptions | null) {
    this.botToken =
      options === null ? undefined : (options?.botToken ?? process.env.TELEGRAM_BOT_TOKEN);
    this.clientId =
      options === null ? undefined : (options?.clientId ?? process.env.TELEGRAM_LOGIN_CLIENT_ID);
    this.keys = options?.keys ?? keys;
  }
  config() {
    return { clientId: this.clientId ?? null, miniApp: Boolean(this.botToken) };
  }
  cookie(token: string | null, secure: boolean) {
    return `${COOKIE}=${token ?? ''}; Path=/auth/telegram; HttpOnly; SameSite=Strict; ${secure ? 'Secure; ' : ''}Max-Age=${token ? AGE / 1000 : 0}`;
  }
  begin(purpose: unknown, owner: string | null) {
    if (!this.botToken && !this.clientId)
      throw new AuthError(503, 'Вход через Telegram временно недоступен.');
    if (purpose !== 'login' && purpose !== 'link')
      throw new AuthError(400, 'Некорректный запрос входа.');
    if (purpose === 'link' && !owner) throw new AuthError(401, 'Сначала войдите в аккаунт.');
    for (const [key, attempt] of this.attempts)
      if (attempt.expires <= Date.now()) this.attempts.delete(key);
    if (this.attempts.size >= 10000) throw new AuthError(503, 'Повторите вход через минуту.');
    const token = randomBytes(32).toString('hex');
    const nonce = randomBytes(32).toString('hex');
    this.attempts.set(createHash('sha256').update(token).digest('hex'), {
      nonce,
      owner,
      purpose,
      expires: Date.now() + AGE,
    });
    return { token, nonce, ...this.config() };
  }
  async complete(cookie: string | undefined, data: Record<string, unknown>, owner: string | null) {
    const token = cookie
      ?.split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith(`${COOKIE}=`))
      ?.slice(COOKIE.length + 1);
    const key =
      token && /^[a-f0-9]{64}$/.test(token) ? createHash('sha256').update(token).digest('hex') : '';
    const attempt = this.attempts.get(key);
    this.attempts.delete(key);
    if (
      !attempt ||
      attempt.expires <= Date.now() ||
      typeof data.nonce !== 'string' ||
      data.nonce !== attempt.nonce
    )
      throw new AuthError(401, 'Сеанс входа истёк. Попробуйте снова.');
    if (owner !== attempt.owner) throw new AuthError(409, 'Аккаунт изменился. Повторите вход.');
    let identity: TelegramUser;
    if (typeof data.initData === 'string' && this.botToken)
      identity = validateTelegramInitData(data.initData, this.botToken);
    else if (typeof data.idToken === 'string' && this.clientId) {
      try {
        const { payload } = await jwtVerify(data.idToken, this.keys, {
          issuer: 'https://oauth.telegram.org',
          audience: this.clientId,
          algorithms: ['RS256', 'ES256'],
          requiredClaims: ['sub', 'exp', 'iat', 'nonce', 'id'],
          maxTokenAge: '5m',
          clockTolerance: 30,
        });
        if (payload.nonce !== attempt.nonce)
          throw new AuthError(401, 'Некорректный сеанс Telegram.');
        identity = user({ id: payload.id, username: payload.preferred_username });
      } catch (error) {
        if (
          error instanceof errors.JWKSTimeout ||
          error instanceof errors.JWKSInvalid ||
          !(error instanceof errors.JOSEError || error instanceof AuthError)
        ) {
          console.warn('Telegram verification temporarily unavailable');
          throw new AuthError(503, 'Telegram временно недоступен. Попробуйте снова.');
        }
        throw new AuthError(401, 'Не удалось подтвердить вход через Telegram. Попробуйте снова.');
      }
    } else throw new AuthError(400, 'Telegram не передал данные входа.');
    return { user: identity, linkOwner: attempt.purpose === 'link' ? attempt.owner : null };
  }
}
