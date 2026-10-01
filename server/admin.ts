import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
const COOKIE = 'four_admin';
const SESSION_AGE = 12 * 60 * 60 * 1000;

type Session = { expires: number };

export async function createAdminPasswordHash(password: string) {
  if (password.length < 12 || password.length > 128)
    throw new Error('Admin password must contain 12 to 128 characters.');
  const salt = randomBytes(16).toString('hex');
  const hash = ((await scrypt(password, salt, 64)) as Buffer).toString('hex');
  return `scrypt$${salt}$${hash}`;
}

export class AdminAccess {
  private sessions = new Map<string, Session>();
  private readonly username: string;
  private readonly passwordHash: string | null;

  constructor(passwordHash = process.env.FOUR_ADMIN_PASSWORD_HASH ?? null) {
    this.username = process.env.FOUR_ADMIN_USERNAME ?? 'admin';
    this.passwordHash = passwordHash;
  }

  enabled() {
    return Boolean(this.passwordHash);
  }

  async login(rawUsername: unknown, rawPassword: unknown) {
    if (!this.passwordHash) throw new Error('Админ-панель не настроена.');
    const parts = this.passwordHash.split('$');
    if (
      typeof rawUsername !== 'string' ||
      typeof rawPassword !== 'string' ||
      parts.length !== 3 ||
      parts[0] !== 'scrypt' ||
      !/^[a-f0-9]{32}$/.test(parts[1]) ||
      !/^[a-f0-9]{128}$/.test(parts[2])
    )
      return null;
    const usernameActual = Buffer.from(rawUsername);
    const usernameExpected = Buffer.from(this.username);
    const usernameMatches =
      usernameActual.length === usernameExpected.length &&
      timingSafeEqual(usernameActual, usernameExpected);
    const actual = (await scrypt(rawPassword, parts[1], 64)) as Buffer;
    const expected = Buffer.from(parts[2], 'hex');
    if (!usernameMatches || !timingSafeEqual(actual, expected)) return null;
    this.prune();
    const token = randomBytes(32).toString('hex');
    this.sessions.set(this.tokenHash(token), { expires: Date.now() + SESSION_AGE });
    return token;
  }

  authenticated(cookieHeader: string | undefined) {
    const token = this.readToken(cookieHeader);
    if (!token) return false;
    const key = this.tokenHash(token);
    const session = this.sessions.get(key);
    if (!session || session.expires <= Date.now()) {
      this.sessions.delete(key);
      return false;
    }
    return true;
  }

  logout(cookieHeader: string | undefined) {
    const token = this.readToken(cookieHeader);
    if (token) this.sessions.delete(this.tokenHash(token));
  }

  cookie(token: string | null, secure: boolean) {
    return `${COOKIE}=${token ?? ''}; Path=/; HttpOnly; SameSite=Strict; ${secure ? 'Secure; ' : ''}${token ? `Max-Age=${SESSION_AGE / 1000}` : 'Max-Age=0'}`;
  }

  private prune() {
    for (const [key, session] of this.sessions)
      if (session.expires <= Date.now()) this.sessions.delete(key);
  }

  private tokenHash(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private readToken(header: string | undefined) {
    const value = header
      ?.split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith(`${COOKIE}=`));
    const token = value?.slice(COOKIE.length + 1);
    return token && /^[a-f0-9]{64}$/.test(token) ? token : null;
  }
}

export function temporaryPassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  const bytes = randomBytes(18);
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join('');
}
