import {
  createHash,
  randomBytes,
  randomInt,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { readFileSync } from 'node:fs';
import { mkdir, rename, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
const SESSION_AGE = 30 * 24 * 60 * 60 * 1000;
const VERIFICATION_AGE = 24 * 60 * 60 * 1000;
const RESET_AGE = 60 * 60 * 1000;
const COOKIE = 'four_session';
type Account = {
  username: string;
  salt: string;
  hash: string;
  createdAt?: number;
  email?: string;
  emailVerified?: boolean;
  disabled?: boolean;
};
type Session = { usernameKey?: string; guestName?: string; expires: number };
type ActionToken = { usernameKey: string; expires: number };
type Database = {
  accounts: Record<string, Account>;
  sessions: Record<string, Session>;
  verificationTokens: Record<string, ActionToken>;
  resetTokens: Record<string, ActionToken>;
};

export class AuthError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

export class AuthStore {
  private data: Database = {
    accounts: Object.create(null),
    sessions: Object.create(null),
    verificationTokens: Object.create(null),
    resetTokens: Object.create(null),
  };
  private writing: Promise<void> = Promise.resolve();
  private file: string | null;

  constructor(file: string | null = process.env.FOUR_AUTH_FILE ?? resolve('data/accounts.json')) {
    this.file = file;
    if (file) {
      try {
        const stored = JSON.parse(readFileSync(file, 'utf8')) as Database;
        if (stored.accounts && stored.sessions)
          this.data = {
            accounts: Object.assign(Object.create(null), stored.accounts),
            sessions: Object.assign(Object.create(null), stored.sessions),
            verificationTokens: Object.assign(Object.create(null), stored.verificationTokens ?? {}),
            resetTokens: Object.assign(Object.create(null), stored.resetTokens ?? {}),
          };
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
      }
    }
  }

  private save() {
    if (!this.file) return Promise.resolve();
    const file = this.file;
    const serialized = JSON.stringify(this.data);
    this.writing = this.writing.then(async () => {
      await mkdir(dirname(file), { recursive: true, mode: 0o700 });
      const temp = `${file}.${randomBytes(8).toString('hex')}.tmp`;
      await writeFile(temp, serialized, { mode: 0o600 });
      await rename(temp, file);
    });
    return this.writing;
  }

  private key(username: string) {
    return username.normalize('NFKC').toLocaleLowerCase('und');
  }

  private validateUsername(username: unknown) {
    if (typeof username !== 'string' || !/^[A-Za-z0-9_]{3,24}$/.test(username.normalize('NFKC')))
      throw new AuthError(
        400,
        'Имя пользователя: от 3 до 24 английских букв, цифр или символов _.',
      );
    return username.normalize('NFKC');
  }

  private validatePassword(password: unknown) {
    if (typeof password !== 'string' || password.length < 8 || password.length > 128)
      throw new AuthError(400, 'Пароль должен содержать от 8 до 128 символов.');
    return password;
  }

  private validate(username: unknown, password: unknown) {
    return {
      username: this.validateUsername(username),
      password: this.validatePassword(password),
    };
  }

  private validateEmail(rawEmail: unknown) {
    if (
      typeof rawEmail !== 'string' ||
      rawEmail.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawEmail)
    )
      throw new AuthError(400, 'Введите корректный email.');
    return rawEmail.normalize('NFKC').trim().toLocaleLowerCase('und');
  }

  async register(
    rawUsername: unknown,
    rawPassword: unknown,
    rawEmail?: unknown,
    requireEmail = false,
  ) {
    const { username, password } = this.validate(rawUsername, rawPassword);
    const key = this.key(username);
    if (this.data.accounts[key]) throw new AuthError(409, 'Это имя пользователя уже занято.');
    const email = requireEmail ? this.validateEmail(rawEmail) : undefined;
    if (
      email &&
      Object.values(this.data.accounts).some(
        (account) => account.email?.toLocaleLowerCase('und') === email,
      )
    )
      throw new AuthError(409, 'Аккаунт с этим email уже существует.');
    const salt = randomBytes(16).toString('hex');
    const hash = ((await scrypt(password, salt, 64)) as Buffer).toString('hex');
    // The second check closes the gap while password hashing was in progress.
    if (this.data.accounts[key]) throw new AuthError(409, 'Это имя пользователя уже занято.');
    if (
      email &&
      Object.values(this.data.accounts).some(
        (account) => account.email?.toLocaleLowerCase('und') === email,
      )
    )
      throw new AuthError(409, 'Аккаунт с этим email уже существует.');
    this.data.accounts[key] = {
      username,
      salt,
      hash,
      createdAt: Date.now(),
      ...(email ? { email, emailVerified: false } : {}),
    };
    if (email) {
      const verificationToken = this.issueToken(
        this.data.verificationTokens,
        key,
        VERIFICATION_AGE,
      );
      await this.save();
      return { username, email, verificationToken };
    }
    const token = this.newSession(key);
    await this.save();
    return { username, token };
  }

  async login(rawUsername: unknown, rawPassword: unknown) {
    if (typeof rawUsername !== 'string' || typeof rawPassword !== 'string')
      throw new AuthError(400, 'Введите имя пользователя и пароль.');
    const key = this.key(rawUsername);
    const account = this.data.accounts[key];
    // Always perform a hash to avoid a cheap username existence oracle.
    const salt = account?.salt ?? '00000000000000000000000000000000';
    const expected = Buffer.from(account?.hash ?? '00'.repeat(64), 'hex');
    const actual = (await scrypt(rawPassword, salt, 64)) as Buffer;
    if (!account || !timingSafeEqual(actual, expected))
      throw new AuthError(401, 'Неверное имя пользователя или пароль.');
    if (account.disabled) throw new AuthError(403, 'Аккаунт заблокирован администратором.');
    if (account.email && !account.emailVerified)
      throw new AuthError(403, 'Подтвердите email по ссылке из письма.');
    const token = this.newSession(key);
    await this.save();
    return { username: account.username, token };
  }

  profile(cookieHeader: string | undefined) {
    const token = this.readToken(cookieHeader);
    if (!token) return null;
    const session = this.data.sessions[this.hashToken(token)];
    if (!session?.usernameKey || session.expires <= Date.now()) return null;
    const account = this.data.accounts[session.usernameKey];
    if (!account || account.disabled) return null;
    return {
      username: account.username,
      email: account.email ?? null,
      emailVerified: Boolean(account.email && account.emailVerified),
      createdAt:
        typeof account.createdAt === 'number' && Number.isSafeInteger(account.createdAt)
          ? account.createdAt
          : null,
    };
  }

  async changePassword(
    cookieHeader: string | undefined,
    rawCurrentPassword: unknown,
    rawNewPassword: unknown,
  ) {
    const token = this.readToken(cookieHeader);
    if (!token) throw new AuthError(401, 'Войдите в аккаунт заново.');
    const session = this.data.sessions[this.hashToken(token)];
    if (!session?.usernameKey || session.expires <= Date.now())
      throw new AuthError(401, 'Войдите в аккаунт заново.');
    const account = this.data.accounts[session.usernameKey];
    if (!account || account.disabled) throw new AuthError(401, 'Войдите в аккаунт заново.');
    if (typeof rawCurrentPassword !== 'string') throw new AuthError(400, 'Введите текущий пароль.');
    const expected = Buffer.from(account.hash, 'hex');
    const actual = (await scrypt(rawCurrentPassword, account.salt, 64)) as Buffer;
    if (!timingSafeEqual(actual, expected)) throw new AuthError(401, 'Текущий пароль неверен.');
    const password = this.validatePassword(rawNewPassword);
    if (password === rawCurrentPassword)
      throw new AuthError(400, 'Новый пароль должен отличаться от текущего.');
    const salt = randomBytes(16).toString('hex');
    account.salt = salt;
    account.hash = ((await scrypt(password, salt, 64)) as Buffer).toString('hex');
    this.invalidateAccount(session.usernameKey);
    const nextToken = this.newSession(session.usernameKey);
    await this.save();
    return { username: account.username, token: nextToken };
  }

  private newSession(usernameKey: string) {
    this.pruneSessions();
    const token = randomBytes(32).toString('hex');
    this.data.sessions[this.hashToken(token)] = { usernameKey, expires: Date.now() + SESSION_AGE };
    return token;
  }

  private issueToken(collection: Record<string, ActionToken>, usernameKey: string, age: number) {
    for (const [tokenHash, token] of Object.entries(collection))
      if (token.usernameKey === usernameKey || token.expires <= Date.now())
        delete collection[tokenHash];
    const raw = randomBytes(32).toString('hex');
    collection[this.hashToken(raw)] = { usernameKey, expires: Date.now() + age };
    return raw;
  }

  private consumeToken(collection: Record<string, ActionToken>, rawToken: unknown) {
    if (typeof rawToken !== 'string' || !/^[a-f0-9]{64}$/.test(rawToken))
      throw new AuthError(400, 'Ссылка недействительна или устарела.');
    const tokenHash = this.hashToken(rawToken);
    const token = collection[tokenHash];
    delete collection[tokenHash];
    if (!token || token.expires <= Date.now())
      throw new AuthError(400, 'Ссылка недействительна или устарела.');
    return token.usernameKey;
  }

  async verifyEmail(rawToken: unknown) {
    const usernameKey = this.consumeToken(this.data.verificationTokens, rawToken);
    const account = this.data.accounts[usernameKey];
    if (!account?.email) throw new AuthError(400, 'Ссылка недействительна или устарела.');
    account.emailVerified = true;
    const token = this.newSession(usernameKey);
    await this.save();
    return { username: account.username, token };
  }

  async resendVerification(rawIdentifier: unknown) {
    if (typeof rawIdentifier !== 'string') return null;
    const normalized = rawIdentifier.normalize('NFKC').trim().toLocaleLowerCase('und');
    const entry = Object.entries(this.data.accounts).find(
      ([usernameKey, account]) => usernameKey === normalized || account.email === normalized,
    );
    if (!entry) return null;
    const [usernameKey, account] = entry;
    if (!account.email || account.emailVerified) return null;
    const token = this.issueToken(this.data.verificationTokens, usernameKey, VERIFICATION_AGE);
    await this.save();
    return { username: account.username, email: account.email, token };
  }

  async requestPasswordReset(rawEmail: unknown) {
    if (typeof rawEmail !== 'string') return null;
    const email = rawEmail.normalize('NFKC').trim().toLocaleLowerCase('und');
    const entry = Object.entries(this.data.accounts).find(
      ([, account]) => account.email === email && account.emailVerified,
    );
    if (!entry) return null;
    const [usernameKey, account] = entry;
    const token = this.issueToken(this.data.resetTokens, usernameKey, RESET_AGE);
    await this.save();
    return { username: account.username, email, token };
  }

  async resetPassword(rawToken: unknown, rawPassword: unknown) {
    const password = this.validatePassword(rawPassword);
    const usernameKey = this.consumeToken(this.data.resetTokens, rawToken);
    const account = this.data.accounts[usernameKey];
    if (!account) throw new AuthError(400, 'Ссылка недействительна или устарела.');
    const salt = randomBytes(16).toString('hex');
    account.salt = salt;
    account.hash = ((await scrypt(password, salt, 64)) as Buffer).toString('hex');
    for (const [tokenHash, session] of Object.entries(this.data.sessions))
      if (session.usernameKey === usernameKey) delete this.data.sessions[tokenHash];
    const token = this.newSession(usernameKey);
    await this.save();
    return { username: account.username, token };
  }

  async createGuest() {
    this.pruneSessions();
    const token = randomBytes(32).toString('hex');
    const name = guestName();
    this.data.sessions[this.hashToken(token)] = {
      guestName: name,
      expires: Date.now() + SESSION_AGE,
    };
    await this.save();
    return { name, token };
  }

  private pruneSessions() {
    for (const [tokenHash, session] of Object.entries(this.data.sessions))
      if (session.expires <= Date.now()) delete this.data.sessions[tokenHash];
  }

  private hashToken(token: string) {
    // Session tokens are high-entropy, so an ordinary cryptographic digest is sufficient.
    return createHash('sha256').update(token).digest('hex');
  }

  identity(cookieHeader: string | undefined) {
    const token = this.readToken(cookieHeader);
    if (!token) return null;
    const session = this.data.sessions[this.hashToken(token)];
    if (!session || session.expires <= Date.now()) return null;
    if (!session.usernameKey) return session.guestName ?? null;
    const account = this.data.accounts[session.usernameKey];
    return account && !account.disabled ? account.username : null;
  }

  username(cookieHeader: string | undefined) {
    const token = this.readToken(cookieHeader);
    if (!token) return null;
    const session = this.data.sessions[this.hashToken(token)];
    if (!session?.usernameKey || session.expires <= Date.now()) return null;
    const account = this.data.accounts[session.usernameKey];
    return account && !account.disabled ? account.username : null;
  }

  leaderboardUsernames() {
    return Object.values(this.data.accounts)
      .filter((account) => !account.disabled && (!account.email || account.emailVerified))
      .map((account) => account.username);
  }

  adminAccounts() {
    return Object.values(this.data.accounts)
      .map((account) => ({
        username: account.username,
        createdAt:
          typeof account.createdAt === 'number' && Number.isSafeInteger(account.createdAt)
            ? account.createdAt
            : null,
        email: account.email ?? '',
        emailVerified: Boolean(account.email && account.emailVerified),
        disabled: Boolean(account.disabled),
      }))
      .sort((a, b) => a.username.localeCompare(b.username, 'ru'));
  }

  async adminUpdate(
    originalUsername: unknown,
    values: {
      username?: unknown;
      email?: unknown;
      emailVerified?: unknown;
      disabled?: unknown;
    },
  ) {
    if (typeof originalUsername !== 'string') throw new AuthError(400, 'Аккаунт не указан.');
    const oldKey = this.key(originalUsername);
    const account = this.data.accounts[oldKey];
    if (!account) throw new AuthError(404, 'Аккаунт не найден.');
    const username = this.validateUsername(values.username ?? account.username);
    const newKey = this.key(username);
    if (newKey !== oldKey && this.data.accounts[newKey])
      throw new AuthError(409, 'Это имя пользователя уже занято.');
    const email =
      typeof values.email === 'string' && !values.email.trim()
        ? undefined
        : values.email === undefined
          ? account.email
          : this.validateEmail(values.email);
    if (
      email &&
      Object.entries(this.data.accounts).some(
        ([key, other]) => key !== oldKey && other.email?.toLocaleLowerCase('und') === email,
      )
    )
      throw new AuthError(409, 'Аккаунт с этим email уже существует.');
    const previousUsername = account.username;
    const securityChanged =
      username !== account.username ||
      email !== account.email ||
      Boolean(email && (values.emailVerified ?? account.emailVerified)) !==
        Boolean(account.emailVerified) ||
      Boolean(values.disabled ?? account.disabled) !== Boolean(account.disabled);
    account.username = username;
    account.email = email;
    account.emailVerified = Boolean(email && (values.emailVerified ?? account.emailVerified));
    account.disabled = Boolean(values.disabled ?? account.disabled);
    if (newKey !== oldKey) {
      delete this.data.accounts[oldKey];
      this.data.accounts[newKey] = account;
    }
    if (securityChanged) this.invalidateAccount(oldKey);
    await this.save();
    return {
      previousUsername,
      securityChanged,
      account: this.adminAccounts().find((a) => a.username === username)!,
    };
  }

  async adminResetPassword(rawUsername: unknown, rawPassword: unknown) {
    if (typeof rawUsername !== 'string') throw new AuthError(400, 'Аккаунт не указан.');
    const key = this.key(rawUsername);
    const account = this.data.accounts[key];
    if (!account) throw new AuthError(404, 'Аккаунт не найден.');
    const password = this.validatePassword(rawPassword);
    const salt = randomBytes(16).toString('hex');
    account.salt = salt;
    account.hash = ((await scrypt(password, salt, 64)) as Buffer).toString('hex');
    this.invalidateAccount(key);
    await this.save();
  }

  async adminDelete(rawUsername: unknown) {
    if (typeof rawUsername !== 'string') throw new AuthError(400, 'Аккаунт не указан.');
    const key = this.key(rawUsername);
    const account = this.data.accounts[key];
    if (!account) throw new AuthError(404, 'Аккаунт не найден.');
    this.invalidateAccount(key);
    delete this.data.accounts[key];
    await this.save();
    return account.username;
  }

  private invalidateAccount(usernameKey: string) {
    for (const [tokenHash, session] of Object.entries(this.data.sessions))
      if (session.usernameKey === usernameKey) delete this.data.sessions[tokenHash];
    for (const collection of [this.data.verificationTokens, this.data.resetTokens])
      for (const [tokenHash, token] of Object.entries(collection))
        if (token.usernameKey === usernameKey) delete collection[tokenHash];
  }

  async logout(cookieHeader: string | undefined) {
    const token = this.readToken(cookieHeader);
    if (token) {
      delete this.data.sessions[this.hashToken(token)];
      await this.save();
    }
  }

  private readToken(header: string | undefined) {
    const value = header
      ?.split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith(`${COOKIE}=`));
    const token = value?.slice(COOKIE.length + 1);
    return token && /^[a-f0-9]{64}$/.test(token) ? token : null;
  }

  cookie(token: string | null, secure: boolean) {
    return `${COOKIE}=${token ?? ''}; Path=/; HttpOnly; SameSite=Lax; ${secure ? 'Secure; ' : ''}${token ? `Max-Age=${SESSION_AGE / 1000}` : 'Max-Age=0'}`;
  }
}

export function guestName() {
  return `Гость_${randomInt(100000, 1000000)}`;
}
