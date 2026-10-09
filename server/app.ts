import { randomBytes, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { createServer, type Server } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { resolve, sep, extname } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import { createGame, makeMove, SIZE, type Player } from '../src/game/core/index.ts';
import type { ClientCommand, LobbySnapshot, ServerEvent } from '../src/network/protocol.ts';
import { AuthError, AuthStore, guestName } from './auth.ts';
import { AdminAccess, temporaryPassword } from './admin.ts';
import { ResendMailer, type Mailer } from './email.ts';
import { StatisticsStore } from './statistics.ts';
import { onlineElapsed } from '../src/network/matchTime.ts';
import type { AnalyticsFilter } from '../src/network/analyticsTypes.ts';
import { DailyService, type DailyServiceOptions } from './dailyService.ts';

interface Seat {
  account: string | null;
  name: string;
  token: string;
  socket: WebSocket | null;
  disconnectedAt: number | null;
}
interface Room {
  pause?: LobbySnapshot['pause'];
  pauseTimer?: ReturnType<typeof setTimeout>;
  pauseRequestAllowedAt?: number;
  ranking?: LobbySnapshot['ranking'];
  turnDeadline?: number;
  endReason?: string;
  id: string;
  statisticsSaved?: boolean;
  code: string;
  kind: 'lobby' | 'quick';
  seats: [Seat, Seat | null];
  game: LobbySnapshot['game'];
  revision: number;
  round: number;
  startedAt: number | null;
  finishedAt: number | null;
  rematch: Player[];
  lastActivity: number;
}
interface PendingMatch {
  id: string;
  players: [
    { socket: WebSocket; name: string; accepted: boolean },
    { socket: WebSocket; name: string; accepted: boolean },
  ];
  deadline: number;
  timer: ReturnType<typeof setTimeout>;
}
interface QuickSearch {
  account: string | null;
  name: string;
  socket: WebSocket;
  disconnectedAt?: number;
  seat?: { room: Room; player: Player };
}
export interface OnlineServerOptions {
  /** Built frontend directory. Set null for an API-only server. */
  staticDir?: string | null;
  disconnectGraceMs?: number;
  idleTimeoutMs?: number;
  cleanupIntervalMs?: number;
  heartbeatIntervalMs?: number;
  maxRooms?: number;
  maxConnections?: number;
  messagesPerMinute?: number;
  matchConfirmMs?: number;
  /** Account database path. Set null for an isolated in-memory test server. */
  authFile?: string | null;
  statsFile?: string | null;
  ratedTurnMs?: number;
  pauseMs?: number;
  pauseRequestMs?: number;
  /** Scrypt admin password hash. Set null to disable the admin API. */
  adminPasswordHash?: string | null;
  /** Transactional email provider. Omit to use Resend from the environment; null disables email. */
  mailer?: Mailer | null;
  daily?: DailyServiceOptions;
}

const mime: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.webp': 'image/webp',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
};
const isRecord = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === 'object' && !Array.isArray(value);
const integer = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
const nameIsValid = (value: unknown): value is string =>
  typeof value === 'string' && value.length <= 200;
const codeIsValid = (value: unknown): value is string =>
  typeof value === 'string' && /^[a-z]{5}$/i.test(value.trim());

function parseCommand(raw: string): ClientCommand | null {
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!isRecord(data)) return null;
  switch (data.type) {
    case 'create':
      return nameIsValid(data.name) ? { type: 'create', name: data.name } : null;
    case 'join':
      return nameIsValid(data.name) && codeIsValid(data.code)
        ? { type: 'join', name: data.name, code: data.code.trim().toUpperCase() }
        : null;
    case 'quick_find':
      return nameIsValid(data.name) &&
        (data.searchId === undefined ||
          (typeof data.searchId === 'string' && /^[a-f0-9]{32}$/.test(data.searchId)))
        ? { type: 'quick_find', name: data.name, searchId: data.searchId }
        : null;
    case 'quick_accept':
    case 'quick_decline':
      return typeof data.matchId === 'string' && /^[a-f0-9]{32}$/.test(data.matchId)
        ? { type: data.type, matchId: data.matchId }
        : null;
    case 'quick_cancel':
      return { type: 'quick_cancel' };
    case 'resume':
      return codeIsValid(data.code) &&
        typeof data.token === 'string' &&
        /^[a-f0-9]{64}$/.test(data.token)
        ? { type: 'resume', code: data.code.trim().toUpperCase(), token: data.token }
        : null;
    case 'move':
      return integer(data.x) &&
        data.x < SIZE &&
        integer(data.y) &&
        data.y < SIZE &&
        integer(data.revision) &&
        integer(data.round)
        ? { type: 'move', x: data.x, y: data.y, revision: data.revision, round: data.round }
        : null;
    case 'rematch':
      return integer(data.round) ? { type: 'rematch', round: data.round } : null;
    case 'pause_request':
      return integer(data.round) ? { type: 'pause_request', round: data.round } : null;
    case 'pause_ready':
      return integer(data.round) ? { type: 'pause_ready', round: data.round } : null;
    case 'pause_answer':
      return integer(data.round) &&
        typeof data.requestId === 'string' &&
        /^[a-f0-9]{32}$/.test(data.requestId) &&
        typeof data.accept === 'boolean'
        ? {
            type: 'pause_answer',
            round: data.round,
            requestId: data.requestId,
            accept: data.accept,
          }
        : null;
    case 'leave':
      return { type: 'leave' };
    default:
      return null;
  }
}

export function createOnlineServer(options: OnlineServerOptions = {}) {
  const auth = new AuthStore(options.authFile);
  const mailer = options.mailer === undefined ? ResendMailer.fromEnv() : options.mailer;
  const statistics = new StatisticsStore(
    options.statsFile === undefined && options.authFile === null ? null : options.statsFile,
  );
  const admin = new AdminAccess(options.adminPasswordHash);
  const daily = new DailyService(statistics, options.daily);
  if (options.authFile !== null || options.daily) daily.start();
  const rooms = new Map<string, Room>();
  const memberships = new WeakMap<WebSocket, { room: Room; player: Player }>();
  const socketNames = new WeakMap<WebSocket, string>();
  const socketAccounts = new WeakMap<WebSocket, string | null>();
  const waiting = new Map<WebSocket, string>();
  const searches = new Map<string, QuickSearch>();
  const searchBySocket = new WeakMap<WebSocket, string>();
  const pendingBySocket = new Map<WebSocket, PendingMatch>();
  const pendingMatches = new Set<PendingMatch>();
  const alive = new WeakSet<WebSocket>();
  const authAttempts = new Map<string, { count: number; until: number }>();
  const mailAttempts = new Map<string, { count: number; until: number }>();
  const adminAttempts = new Map<string, { count: number; until: number }>();
  const telemetryAttempts = new Map<string, { count: number; until: number }>();
  const dailyAttempts = new Map<string, { count: number; until: number }>();
  const staticRoot = options.staticDir === null ? null : resolve(options.staticDir ?? 'dist');
  const graceMs = options.disconnectGraceMs ?? 5 * 60_000;
  const idleMs = options.idleTimeoutMs ?? 2 * 60 * 60_000;
  let shuttingDown = false;

  const httpServer: Server = createServer((req, res) => {
    void (async () => {
      const requestUrl = new URL(req.url ?? '/', 'http://localhost');
      const pathname = decodeURIComponent(requestUrl.pathname);
      if (pathname === '/daily' || pathname === '/daily/results') {
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        const respond = (status: number, body: object) =>
          res.writeHead(status).end(JSON.stringify(body));
        const localProxy = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(
          req.socket.remoteAddress ?? '',
        );
        const address =
          localProxy && typeof req.headers['x-real-ip'] === 'string'
            ? req.headers['x-real-ip']
            : (req.socket.remoteAddress ?? 'unknown');
        const rate = (key: string, limit: number) => {
          const now = Date.now();
          const previous = dailyAttempts.get(key);
          const attempt =
            previous && previous.until > now
              ? { count: previous.count + 1, until: previous.until }
              : { count: 1, until: now + 60_000 };
          dailyAttempts.set(key, attempt);
          if (attempt.count > limit)
            throw new AuthError(429, 'Слишком много попыток. Подождите минуту.');
        };
        try {
          if (pathname === '/daily' && req.method === 'GET') {
            rate(`read:${address}`, 120);
            respond(
              200,
              await daily.read(auth.username(req.headers.cookie), auth.leaderboardUsernames()),
            );
            return;
          }
          if (pathname !== '/daily/results' || req.method !== 'POST') {
            res.setHeader('Allow', pathname === '/daily' ? 'GET' : 'POST');
            throw new AuthError(405, 'Метод не поддерживается.');
          }
          const owner = auth.username(req.headers.cookie);
          if (!owner) throw new AuthError(401, 'Войдите в аккаунт, чтобы сохранить результат.');
          if (req.headers.origin) {
            let allowed = false;
            try {
              const origin = new URL(req.headers.origin);
              const dev =
                process.env.NODE_ENV !== 'production' &&
                localProxy &&
                origin.port === '5173' &&
                ['localhost', '127.0.0.1'].includes(origin.hostname);
              allowed = origin.host === req.headers.host || dev;
            } catch {
              /* Invalid origin is rejected below. */
            }
            if (!allowed) throw new AuthError(403, 'Запрос с другого сайта отклонён.');
          }
          rate(`submit:${address}`, 30);
          rate(`account:${owner}`, 20);
          if (!req.headers['content-type']?.startsWith('application/json'))
            throw new AuthError(415, 'Ожидается JSON-запрос.');
          const chunks: Buffer[] = [];
          let size = 0;
          for await (const chunk of req) {
            size += chunk.length;
            if (size > 8192) throw new AuthError(413, 'Слишком большой запрос.');
            chunks.push(Buffer.from(chunk));
          }
          let body: unknown;
          try {
            body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          } catch {
            throw new AuthError(400, 'Некорректный JSON.');
          }
          respond(
            200,
            await daily.submit(
              owner,
              auth.leaderboardUsernames(),
              body,
              () => auth.username(req.headers.cookie) === owner,
            ),
          );
        } catch (error) {
          respond(error instanceof AuthError ? error.status : 500, {
            error:
              error instanceof AuthError
                ? error.message
                : 'Не удалось загрузить задачу дня. Попробуйте снова.',
          });
        }
        return;
      }
      if (pathname === '/telemetry') {
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        try {
          if (req.method !== 'POST') throw new AuthError(405, 'Метод не поддерживается.');
          const localProxy = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(
            req.socket.remoteAddress ?? '',
          );
          if (req.headers.origin) {
            const origin = new URL(req.headers.origin);
            const dev =
              process.env.NODE_ENV !== 'production' &&
              localProxy &&
              origin.port === '5173' &&
              ['localhost', '127.0.0.1'].includes(origin.hostname);
            if (origin.host !== req.headers.host && !dev)
              throw new AuthError(403, 'Запрос с другого сайта отклонён.');
          }
          if (req.headers['sec-fetch-site'] === 'cross-site')
            throw new AuthError(403, 'Запрос с другого сайта отклонён.');
          if (!req.headers['content-type']?.startsWith('application/json'))
            throw new AuthError(415, 'Ожидается JSON-запрос.');
          const address =
            localProxy && typeof req.headers['x-real-ip'] === 'string'
              ? req.headers['x-real-ip']
              : (req.socket.remoteAddress ?? 'unknown');
          const now = Date.now(),
            previous = telemetryAttempts.get(address);
          const attempt =
            previous && previous.until > now
              ? { count: previous.count + 1, until: previous.until }
              : { count: 1, until: now + 60000 };
          telemetryAttempts.set(address, attempt);
          if (attempt.count > 240) throw new AuthError(429, 'Слишком много событий.');
          let body = '';
          for await (const chunk of req) {
            body += chunk;
            if (body.length > 16000) throw new AuthError(413, 'Слишком большой запрос.');
          }
          let data: unknown;
          try {
            data = JSON.parse(body);
          } catch {
            throw new AuthError(400, 'Некорректный JSON.');
          }
          if (!isRecord(data)) throw new AuthError(400, 'Некорректное событие.');
          statistics.analytics.ingest(
            data,
            auth.username(req.headers.cookie),
            auth.identity(req.headers.cookie),
          );
          res.writeHead(204).end();
        } catch (error) {
          res.writeHead(error instanceof AuthError ? error.status : 500).end(
            JSON.stringify({
              error: error instanceof AuthError ? error.message : 'Не удалось сохранить событие.',
            }),
          );
        }
        return;
      }
      if (pathname === '/auth/leaderboard') {
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        if (req.method !== 'GET') {
          res.setHeader('Allow', 'GET');
          res.writeHead(405).end(JSON.stringify({ error: 'Метод не поддерживается.' }));
          return;
        }
        res.writeHead(200).end(
          JSON.stringify({
            players: statistics.leaderboard(auth.leaderboardUsernames()),
          }),
        );
        return;
      }
      if (pathname.startsWith('/admin-api/')) {
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.setHeader('X-Frame-Options', 'DENY');
        const respond = (status: number, body: object) =>
          res.writeHead(status).end(JSON.stringify(body));
        const localProxy = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(
          req.socket.remoteAddress ?? '',
        );
        const secure = req.headers['x-forwarded-proto'] === 'https' && localProxy;
        const address =
          localProxy && typeof req.headers['x-real-ip'] === 'string'
            ? req.headers['x-real-ip']
            : (req.socket.remoteAddress ?? 'unknown');
        const readJson = async () => {
          if (!req.headers['content-type']?.startsWith('application/json'))
            throw new AuthError(415, 'Ожидается JSON-запрос.');
          let body = '';
          for await (const chunk of req) {
            body += chunk;
            if (body.length > 8192) throw new AuthError(413, 'Слишком большой запрос.');
          }
          try {
            const data: unknown = JSON.parse(body);
            if (!isRecord(data)) throw new Error('not an object');
            return data;
          } catch {
            throw new AuthError(400, 'Некорректный JSON.');
          }
        };
        if (req.method === 'POST' || req.method === 'PATCH' || req.method === 'DELETE') {
          try {
            if (req.headers.origin) {
              const origin = new URL(req.headers.origin);
              const localDev =
                process.env.NODE_ENV !== 'production' &&
                localProxy &&
                origin.port === '5173' &&
                ['localhost', '127.0.0.1'].includes(origin.hostname);
              if (origin.host !== req.headers.host && !localDev)
                throw new AuthError(403, 'Запрос с другого сайта отклонён.');
            }
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 403, {
              error: 'Запрос с другого сайта отклонён.',
            });
            return;
          }
        }
        try {
          if (pathname === '/admin-api/login' && req.method === 'POST') {
            const previous = adminAttempts.get(address);
            const now = Date.now();
            const attempt =
              previous && previous.until > now
                ? { count: previous.count + 1, until: previous.until }
                : { count: 1, until: now + 60_000 };
            adminAttempts.set(address, attempt);
            if (attempt.count > 10)
              throw new AuthError(429, 'Слишком много попыток. Подождите минуту.');
            const data = await readJson();
            const token = await admin.login(data.username, data.password);
            if (!token) throw new AuthError(401, 'Неверный логин или пароль.');
            adminAttempts.delete(address);
            res.setHeader('Set-Cookie', admin.cookie(token, secure));
            respond(200, { authenticated: true });
            return;
          }
          if (pathname === '/admin-api/me' && req.method === 'GET') {
            respond(200, {
              configured: admin.enabled(),
              authenticated: admin.authenticated(req.headers.cookie),
            });
            return;
          }
          if (pathname === '/admin-api/logout' && req.method === 'POST') {
            admin.logout(req.headers.cookie);
            res.setHeader('Set-Cookie', admin.cookie(null, secure));
            respond(200, { authenticated: false });
            return;
          }
          if (!admin.authenticated(req.headers.cookie))
            throw new AuthError(401, 'Войдите в админ-панель.');
          if (pathname === '/admin-api/analytics' && req.method === 'GET') {
            const today = new Date(Date.now() + 3 * 3600000).toISOString().slice(0, 10);
            const monthAgo = new Date(Date.now() + 3 * 3600000 - 29 * 86400000)
              .toISOString()
              .slice(0, 10);
            const filter: AnalyticsFilter = {
              from: requestUrl.searchParams.get('from') ?? monthAgo,
              to: requestUrl.searchParams.get('to') ?? today,
              mode: (requestUrl.searchParams.get('mode') ?? 'all') as AnalyticsFilter['mode'],
              device: (requestUrl.searchParams.get('device') ?? 'all') as AnalyticsFilter['device'],
            };
            respond(200, statistics.analytics.dashboard(filter, auth.adminAccounts()));
            return;
          }
          if (pathname === '/admin-api/accounts' && req.method === 'GET') {
            const query = (requestUrl.searchParams.get('q') ?? '').trim().toLocaleLowerCase('und');
            const page = Math.max(1, Number(requestUrl.searchParams.get('page')) || 1);
            const pageSize = Math.min(
              100,
              Math.max(10, Number(requestUrl.searchParams.get('pageSize')) || 25),
            );
            const accounts = auth
              .adminAccounts()
              .map((account) => ({ ...account, ...statistics.adminSummary(account.username) }))
              .filter(
                (account) =>
                  !query ||
                  account.username.toLocaleLowerCase('und').includes(query) ||
                  account.email.toLocaleLowerCase('und').includes(query),
              );
            const offset = (page - 1) * pageSize;
            respond(200, {
              accounts: accounts.slice(offset, offset + pageSize),
              total: accounts.length,
              page,
              pageSize,
            });
            return;
          }
          if (pathname === '/admin-api/accounts' && req.method === 'PATCH') {
            const data = await readJson();
            const originalUsername = data.originalUsername;
            const result = await auth.adminUpdate(originalUsername, data);
            if (result.previousUsername !== result.account.username)
              statistics.renameOwner(result.previousUsername, result.account.username);
            if (data.rating !== undefined) {
              if (typeof data.rating !== 'number')
                throw new AuthError(400, 'Elo должен быть числом.');
              statistics.setRating(result.account.username, data.rating);
            }
            if (result.securityChanged) disconnectAccount(result.previousUsername);
            respond(200, {
              account: {
                ...result.account,
                ...statistics.adminSummary(result.account.username),
              },
            });
            return;
          }
          if (pathname === '/admin-api/accounts/reset-password' && req.method === 'POST') {
            const data = await readJson();
            const password = temporaryPassword();
            await auth.adminResetPassword(data.username, password);
            if (typeof data.username === 'string') disconnectAccount(data.username);
            respond(200, { temporaryPassword: password });
            return;
          }
          if (pathname === '/admin-api/accounts' && req.method === 'DELETE') {
            const data = await readJson();
            if (typeof data.username !== 'string' || data.confirmation !== data.username)
              throw new AuthError(400, 'Для удаления введите точное имя пользователя.');
            if (!auth.adminAccounts().some((account) => account.username === data.username))
              throw new AuthError(404, 'Аккаунт не найден.');
            discardAccountActivity(data.username);
            const username = await auth.adminDelete(data.username);
            statistics.deleteOwner(username);
            respond(200, { deleted: true, username });
            return;
          }
          throw new AuthError(404, 'Адрес не найден.');
        } catch (error) {
          respond(error instanceof AuthError ? error.status : 500, {
            error:
              error instanceof AuthError
                ? error.message
                : 'Операция не выполнена. Повторите позже.',
          });
        }
        return;
      }
      if (pathname.startsWith('/auth/')) {
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        const respond = (status: number, body: object) =>
          res.writeHead(status).end(JSON.stringify(body));
        const localProxy = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(
          req.socket.remoteAddress ?? '',
        );
        const secure = req.headers['x-forwarded-proto'] === 'https' && localProxy;
        const address =
          localProxy && typeof req.headers['x-real-ip'] === 'string'
            ? req.headers['x-real-ip']
            : (req.socket.remoteAddress ?? 'unknown');
        const checkRate = (
          attempts: Map<string, { count: number; until: number }>,
          limit: number,
        ) => {
          const previous = attempts.get(address);
          const now = Date.now();
          const attempt =
            previous && previous.until > now
              ? { count: previous.count + 1, until: previous.until }
              : { count: 1, until: now + 60_000 };
          attempts.set(address, attempt);
          if (attempt.count > limit)
            throw new AuthError(429, 'Слишком много попыток. Подождите минуту.');
        };
        const readAuthJson = async () => {
          if (!req.headers['content-type']?.startsWith('application/json'))
            throw new AuthError(415, 'Ожидается JSON-запрос.');
          let body = '';
          for await (const chunk of req) {
            body += chunk;
            if (body.length > 4096) throw new AuthError(413, 'Слишком большой запрос.');
          }
          try {
            const data: unknown = JSON.parse(body);
            if (!isRecord(data)) throw new Error('not an object');
            return data;
          } catch {
            throw new AuthError(400, 'Некорректный JSON.');
          }
        };
        if (req.method === 'POST' && req.headers.origin) {
          try {
            const origin = new URL(req.headers.origin);
            const localDev =
              process.env.NODE_ENV !== 'production' &&
              localProxy &&
              origin.port === '5173' &&
              ['localhost', '127.0.0.1'].includes(origin.hostname);
            if (origin.host !== req.headers.host && !localDev) {
              respond(403, { error: 'Запрос с другого сайта отклонён.' });
              return;
            }
          } catch {
            respond(403, { error: 'Запрос с другого сайта отклонён.' });
            return;
          }
        }
        if (pathname === '/auth/levels') {
          try {
            const owner = auth.username(req.headers.cookie);
            if (!owner) throw new AuthError(401, 'Войдите в аккаунт, чтобы сохранить уровни.');
            if (req.method === 'GET') respond(200, statistics.levelProgress(owner));
            else if (req.method === 'POST') {
              const data = await readAuthJson();
              if (data.owner !== owner)
                throw new AuthError(403, 'Аккаунт изменился. Обновите страницу.');
              respond(200, statistics.mergeLevelProgress(owner, data.best));
            } else throw new AuthError(405, 'Метод не поддерживается.');
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 500, {
              error: error instanceof AuthError ? error.message : 'Не удалось сохранить уровни.',
            });
          }
          return;
        }
        if (pathname === '/auth/history' || pathname.startsWith('/auth/history/')) {
          try {
            const owner = auth.username(req.headers.cookie);
            if (!owner) throw new AuthError(401, 'Войдите в аккаунт, чтобы открыть статистику.');
            if (pathname === '/auth/history' && req.method === 'GET') {
              respond(200, statistics.read(owner));
              return;
            }
            if (req.method !== 'POST') throw new AuthError(405, 'Метод не поддерживается.');
            if (!req.headers['content-type']?.startsWith('application/json'))
              throw new AuthError(415, 'Ожидается JSON-запрос.');
            const chunks: Buffer[] = [];
            let size = 0;
            for await (const chunk of req) {
              size += chunk.length;
              if (size > 20000) throw new AuthError(413, 'Слишком большой запрос.');
              chunks.push(Buffer.from(chunk));
            }
            let data: unknown;
            try {
              data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            } catch {
              throw new AuthError(400, 'Некорректный JSON.');
            }
            if (!isRecord(data)) throw new AuthError(400, 'Некорректный запрос.');
            if (data.owner !== owner)
              throw new AuthError(403, 'Аккаунт изменился. Обновите страницу.');
            if (pathname === '/auth/history') statistics.saveLocal(owner, data);
            else {
              if (typeof data.id !== 'string' || data.id.length > 140)
                throw new AuthError(400, 'Некорректная партия.');
              if (pathname === '/auth/history/rename' && typeof data.title === 'string')
                statistics.rename(owner, data.id, data.title);
              else if (pathname === '/auth/history/remove') statistics.remove(owner, data.id);
              else throw new AuthError(404, 'Адрес не найден.');
            }
            respond(200, statistics.read(owner));
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 500, {
              error:
                error instanceof AuthError
                  ? error.message
                  : 'Не удалось сохранить статистику. Попробуйте ещё раз.',
            });
          }
          return;
        }
        if (pathname === '/auth/me' && req.method === 'GET') {
          const profile = auth.profile(req.headers.cookie);
          if (profile) respond(200, { authenticated: true, ...profile, guestName: null });
          else {
            const existing = auth.identity(req.headers.cookie);
            const guest = existing ? { name: existing, token: null } : await auth.createGuest();
            if (guest.token) res.setHeader('Set-Cookie', auth.cookie(guest.token, secure));
            respond(200, { authenticated: false, username: null, guestName: guest.name });
          }
          return;
        }
        if (pathname === '/auth/password/change' && req.method === 'POST') {
          try {
            checkRate(authAttempts, 30);
            const data = await readAuthJson();
            const result = await auth.changePassword(
              req.headers.cookie,
              data.currentPassword,
              data.newPassword,
            );
            res.setHeader('Set-Cookie', auth.cookie(result.token, secure));
            respond(200, {
              authenticated: true,
              username: result.username,
              message: 'Пароль изменён. Остальные сеансы завершены.',
            });
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 400, {
              error: error instanceof AuthError ? error.message : 'Не удалось изменить пароль.',
            });
          }
          return;
        }
        if (pathname === '/auth/verify' && req.method === 'POST') {
          try {
            checkRate(mailAttempts, 10);
            const data = await readAuthJson();
            const result = await auth.verifyEmail(data.token);
            res.setHeader('Set-Cookie', auth.cookie(result.token, secure));
            respond(200, {
              authenticated: true,
              username: result.username,
              emailVerified: true,
            });
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 400, {
              error: error instanceof AuthError ? error.message : 'Не удалось подтвердить email.',
            });
          }
          return;
        }
        if (pathname === '/auth/verify' && req.method === 'GET') {
          try {
            const result = await auth.verifyEmail(requestUrl.searchParams.get('token'));
            res.setHeader('Set-Cookie', auth.cookie(result.token, secure));
            res.writeHead(303, { Location: '/?emailVerified=1' }).end();
          } catch {
            res.writeHead(303, { Location: '/?emailVerified=0' }).end();
          }
          return;
        }
        if (pathname === '/auth/logout' && req.method === 'POST') {
          await auth.logout(req.headers.cookie);
          const guest = await auth.createGuest();
          res.setHeader('Set-Cookie', auth.cookie(guest.token, secure));
          respond(200, { authenticated: false, username: null, guestName: guest.name });
          return;
        }
        if (pathname === '/auth/resend-verification' && req.method === 'POST') {
          try {
            checkRate(mailAttempts, 5);
            if (!mailer) throw new AuthError(503, 'Отправка писем временно недоступна.');
            const data = await readAuthJson();
            const pending = await auth.resendVerification(data.identifier);
            if (pending) await mailer.sendVerification(pending);
            respond(200, {
              message: 'Если аккаунт ожидает подтверждения, новое письмо уже отправлено.',
            });
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 503, {
              error:
                error instanceof AuthError
                  ? error.message
                  : 'Не удалось отправить письмо. Попробуйте позже.',
            });
          }
          return;
        }
        if (pathname === '/auth/password-reset/request' && req.method === 'POST') {
          try {
            checkRate(mailAttempts, 5);
            if (!mailer) throw new AuthError(503, 'Отправка писем временно недоступна.');
            const data = await readAuthJson();
            const pending = await auth.requestPasswordReset(data.email);
            if (pending) {
              try {
                await mailer.sendPasswordReset(pending);
              } catch (error) {
                console.error('Password reset email failed:', error);
              }
            }
            respond(200, {
              message: 'Если аккаунт с таким email существует, письмо уже отправлено.',
            });
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 503, {
              error:
                error instanceof AuthError
                  ? error.message
                  : 'Не удалось обработать запрос. Попробуйте позже.',
            });
          }
          return;
        }
        if (pathname === '/auth/password-reset/complete' && req.method === 'POST') {
          try {
            checkRate(authAttempts, 30);
            const data = await readAuthJson();
            const result = await auth.resetPassword(data.token, data.password);
            res.setHeader('Set-Cookie', auth.cookie(result.token, secure));
            respond(200, { authenticated: true, username: result.username });
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 400, {
              error: error instanceof AuthError ? error.message : 'Не удалось изменить пароль.',
            });
          }
          return;
        }
        if (
          (pathname === '/auth/register' || pathname === '/auth/login') &&
          req.method === 'POST'
        ) {
          try {
            checkRate(authAttempts, 30);
            if (pathname === '/auth/register') checkRate(mailAttempts, 5);
            const data = await readAuthJson();
            if (
              pathname === '/auth/register' &&
              mailer?.validateRecipient &&
              typeof data.email === 'string' &&
              !(await mailer.validateRecipient(data.email))
            )
              throw new AuthError(
                400,
                'У этого домена не найден почтовый сервер. Проверьте адрес email.',
              );
            const result =
              pathname === '/auth/register'
                ? await auth.register(data.username, data.password, data.email, !!mailer)
                : await auth.login(data.username, data.password);
            if ('verificationToken' in result) {
              try {
                await mailer!.sendVerification({
                  email: result.email,
                  username: result.username,
                  token: result.verificationToken,
                });
                respond(202, {
                  verificationRequired: true,
                  email: result.email,
                  message:
                    'Письмо с подтверждением отправлено. Проверьте «Входящие» и папку «Спам».',
                });
              } catch (error) {
                console.error('Registration email failed:', error);
                respond(503, {
                  verificationRequired: true,
                  email: result.email,
                  error: 'Аккаунт создан, но письмо не отправлено. Повторите отправку позже.',
                });
              }
              return;
            }
            res.setHeader('Set-Cookie', auth.cookie(result.token, secure));
            respond(200, { authenticated: true, username: result.username });
          } catch (error) {
            respond(error instanceof AuthError ? error.status : 400, {
              error: error instanceof AuthError ? error.message : 'Не удалось обработать запрос.',
            });
          }
          return;
        }
        respond(404, { error: 'Адрес не найден.' });
        return;
      }
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        res.writeHead(405, { Allow: 'GET, HEAD' }).end();
        return;
      }
      if (pathname.includes('\\')) {
        res.writeHead(403).end();
        return;
      }
      if (pathname === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        res.end(req.method === 'HEAD' ? undefined : JSON.stringify({ ok: true }));
        return;
      }
      if (!staticRoot || pathname.includes('\0')) {
        res.writeHead(404).end();
        return;
      }
      let filename = resolve(staticRoot, `.${pathname}`);
      if (filename !== staticRoot && !filename.startsWith(`${staticRoot}${sep}`)) {
        res.writeHead(403).end();
        return;
      }
      let fileStat = await stat(filename).catch(() => null);
      if (!fileStat?.isFile()) {
        if (extname(pathname)) {
          res.writeHead(404).end();
          return;
        }
        filename = resolve(staticRoot, 'index.html');
        fileStat = await stat(filename).catch(() => null);
      }
      if (!fileStat?.isFile()) {
        res.writeHead(404).end();
        return;
      }
      const video = ['.mp4', '.webm'].includes(extname(filename));
      const appleAppSiteAssociation = filename.endsWith(
        `${sep}.well-known${sep}apple-app-site-association`,
      );
      let start = 0;
      let end = fileStat.size - 1;
      const range = video && req.method === 'GET' ? req.headers.range : undefined;
      if (range) {
        const match = /^bytes=(\d*)-(\d*)$/.exec(range);
        if (match && (match[1] || match[2])) {
          start = match[1] ? Number(match[1]) : Math.max(0, fileStat.size - Number(match[2]));
          end = match[1] && match[2] ? Math.min(Number(match[2]), end) : end;
        }
        if (
          !match ||
          (!match[1] && !match[2]) ||
          !Number.isSafeInteger(start) ||
          !Number.isSafeInteger(end) ||
          start > end ||
          start >= fileStat.size
        ) {
          res.writeHead(416, { 'Content-Range': `bytes */${fileStat.size}` }).end();
          return;
        }
      }
      res.writeHead(range ? 206 : 200, {
        'Content-Type': appleAppSiteAssociation
          ? 'application/json'
          : (mime[extname(filename)] ?? 'application/octet-stream'),
        'Content-Length': range ? end - start + 1 : fileStat.size,
        ...(video ? { 'Accept-Ranges': 'bytes' } : {}),
        ...(range ? { 'Content-Range': `bytes ${start}-${end}/${fileStat.size}` } : {}),
        'Cache-Control': extname(filename) === '.html' ? 'no-cache' : 'public, max-age=3600',
        'X-Content-Type-Options': 'nosniff',
      });
      if (req.method === 'HEAD') res.end();
      else
        createReadStream(filename, range ? { start, end } : undefined)
          .on('error', () => res.destroy())
          .pipe(res);
    })().catch(() => {
      if (!res.headersSent) res.writeHead(400);
      res.end();
    });
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 2048 });
  httpServer.on('upgrade', (request, socket, head) => {
    if (request.headers.origin) {
      let allowed = false;
      try {
        const origin = new URL(request.headers.origin);
        const localProxy = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(
          request.socket.remoteAddress ?? '',
        );
        allowed =
          origin.host === request.headers.host ||
          (process.env.NODE_ENV !== 'production' &&
            localProxy &&
            origin.port === '5173' &&
            ['localhost', '127.0.0.1'].includes(origin.hostname));
      } catch {
        /* Invalid origin. */
      }
      if (!allowed) {
        socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
        socket.destroy();
        return;
      }
    }
    if (
      shuttingDown ||
      request.url?.split('?')[0] !== '/online' ||
      wss.clients.size >= (options.maxConnections ?? 2000)
    ) {
      socket.write('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => wss.emit('connection', ws, request));
  });

  function send(ws: WebSocket, event: ServerEvent) {
    if (ws.readyState !== WebSocket.OPEN) return;
    if (ws.bufferedAmount > 256 * 1024) {
      ws.terminate();
      return;
    }
    ws.send(JSON.stringify(event));
  }
  function error(ws: WebSocket, code: string, message: string) {
    send(ws, { type: 'error', code, message });
  }
  function disconnectAccount(username: string) {
    for (const socket of wss.clients) {
      if (socketAccounts.get(socket) !== username) continue;
      send(socket, {
        type: 'closed',
        message: 'Данные аккаунта изменены администратором. Войдите снова.',
      });
      socket.close(4002, 'Account changed');
    }
  }
  function discardAccountActivity(username: string) {
    for (const room of [...rooms.values()]) {
      if (!room.seats.some((seat) => seat?.account === username)) continue;
      clearTimeout(room.pauseTimer);
      rooms.delete(room.code);
      for (const seat of room.seats) {
        if (!seat?.socket) continue;
        memberships.delete(seat.socket);
        send(seat.socket, {
          type: 'closed',
          message:
            seat.account === username
              ? 'Ваш аккаунт удалён администратором.'
              : 'Аккаунт соперника удалён. Партия отменена.',
        });
        if (seat.account === username) seat.socket.close(4002, 'Account deleted');
        seat.socket = null;
      }
    }
    disconnectAccount(username);
    pairWaiting();
  }
  function snapshot(room: Room): LobbySnapshot {
    const publicSeat = (seat: Seat) => ({
      name: seat.name,
      connected: seat.socket?.readyState === WebSocket.OPEN,
    });
    return {
      code: room.code,
      kind: room.kind,
      game: room.game,
      players: [publicSeat(room.seats[0]), room.seats[1] ? publicSeat(room.seats[1]) : null],
      revision: room.revision,
      round: room.round,
      startedAt: room.startedAt,
      finishedAt: room.finishedAt,
      rematch: room.rematch,
      ranking: room.ranking,
      turnDeadline: room.turnDeadline,
      endReason: room.endReason,
      pause: room.pause,
    };
  }
  function broadcast(room: Room) {
    const event: ServerEvent = { type: 'state', snapshot: snapshot(room) };
    for (const seat of room.seats) if (seat?.socket) send(seat.socket, event);
  }
  function closeRoom(room: Room, message: string) {
    if (!persistRoom(room)) return;
    if (room.startedAt && room.game.status === 'playing')
      statistics.analytics.onlineAbandon(`online-${room.id}-${room.round}`);
    clearTimeout(room.pauseTimer);
    rooms.delete(room.code);
    for (const seat of room.seats) {
      if (!seat?.socket) continue;
      memberships.delete(seat.socket);
      send(seat.socket, { type: 'closed', message });
      seat.socket = null;
    }
    pairWaiting();
  }
  function roomExpired(room: Room, now: number) {
    updatePause(room, now);
    expireTimedGame(room, now);
    return (
      now - room.lastActivity >= idleMs ||
      room.seats.some(
        (seat) =>
          seat &&
          seat.disconnectedAt !== null &&
          !room.pause?.endsAt &&
          now - seat.disconnectedAt >= graceMs,
      )
    );
  }
  function forfeit(room: Room, loser: Player, reason: string) {
    if (room.game.status !== 'playing') return;
    finishPause(room, Date.now());
    room.game = { ...room.game, status: 'won', winner: loser === 1 ? 2 : 1, winningLines: [] };
    room.endReason = reason;
    room.finishedAt = Date.now();
    room.turnDeadline = undefined;
    room.revision++;
    persistRoom(room);
    broadcast(room);
  }
  function expireTimedGame(room: Room, now: number) {
    if (room.kind !== 'quick' || room.game.status !== 'playing' || room.pause?.endsAt) return;
    const deadlines = room.seats.flatMap((seat, index) =>
      seat?.disconnectedAt == null
        ? []
        : [
            {
              at: seat.disconnectedAt + Math.min(graceMs, 60000),
              player: (index + 1) as Player,
              reason: 'Поражение за отключение',
            },
          ],
    );
    if (room.turnDeadline)
      deadlines.push({
        at: room.turnDeadline,
        player: room.game.currentPlayer,
        reason: 'Время хода истекло',
      });
    deadlines.sort((a, b) => a.at - b.at);
    if (deadlines[0]?.at <= now) forfeit(room, deadlines[0].player, deadlines[0].reason);
  }
  function finishPause(room: Room, now: number) {
    clearTimeout(room.pauseTimer);
    const pause = room.pause;
    if (!pause) return;
    if (pause.startedAt !== undefined && pause.endsAt !== undefined) {
      const end = Math.min(now, pause.endsAt);
      // The full pause was credited at acceptance; return unused time on an early resume.
      if (room.turnDeadline) room.turnDeadline -= pause.endsAt - end;
      pause.totalMs += Math.max(0, end - pause.startedAt);
      for (const seat of room.seats)
        if (seat?.disconnectedAt != null)
          seat.disconnectedAt += Math.max(0, end - Math.max(pause.startedAt, seat.disconnectedAt));
    }
    pause.startedAt = undefined;
    pause.endsAt = undefined;
    pause.request = undefined;
    pause.ready = undefined;
  }
  function updatePause(room: Room, now: number) {
    const pause = room.pause;
    if (!pause) return;
    if (
      (pause.endsAt !== undefined && now >= pause.endsAt) ||
      (pause.request && now >= pause.request.expiresAt)
    ) {
      finishPause(room, now);
      room.revision++;
      broadcast(room);
    }
  }
  function schedulePause(room: Room, deadline: number) {
    clearTimeout(room.pauseTimer);
    room.pauseTimer = setTimeout(
      () => {
        if (!rooms.has(room.code)) return;
        // Timers may fire just before the wall-clock deadline (notably on Windows).
        if (Date.now() < deadline) {
          schedulePause(room, deadline);
          return;
        }
        updatePause(room, Date.now());
      },
      Math.max(1, deadline - Date.now()),
    );
    room.pauseTimer.unref();
  }
  function makeSeat(name: string, player: Player, socket: WebSocket): Seat {
    return {
      account: socketAccounts.get(socket) ?? null,
      name:
        Array.from(name)
          .filter((character) => character.charCodeAt(0) >= 32 && character.charCodeAt(0) !== 127)
          .join('')
          .trim()
          .slice(0, 24) || `Игрок ${player}`,
      token: randomBytes(32).toString('hex'),
      socket,
      disconnectedAt: null,
    };
  }
  function trackOnlineStart(room: Room) {
    if (!room.startedAt || !room.seats[1]) return;
    statistics.analytics.onlineStart(
      `online-${room.id}-${room.round}`,
      room.kind === 'quick' ? 'ranked' : 'lobby',
      [room.seats[0].account, room.seats[1].account],
      room.startedAt,
      [room.seats[0].name, room.seats[1].name],
    );
  }
  function persistRoom(room: Room): boolean {
    if (room.game.status === 'playing' || room.statisticsSaved) return true;
    try {
      statistics.analytics.onlineEnd(
        `online-${room.id}-${room.round}`,
        room.game,
        onlineElapsed(room),
        room.finishedAt!,
      );
      const changes = statistics.record(
        `online-${room.id}-${room.round}`,
        room.game,
        [room.seats[0].name, room.seats[1]!.name],
        'online',
        onlineElapsed(room),
        room.finishedAt!,
        room.seats.flatMap((seat, index) =>
          seat?.account ? [{ owner: seat.account, player: (index + 1) as Player }] : [],
        ),
        room.ranking?.rated,
        room.endReason,
      );
      if (changes && room.ranking) room.ranking.changes = changes;
      room.statisticsSaved = true;
      return true;
    } catch (error) {
      console.error('Could not save completed online match', error);
      return false;
    }
  }
  function newCode(): string {
    let code: string;
    do {
      code = Array.from({ length: 5 }, () => String.fromCharCode(65 + randomInt(26))).join('');
    } while (rooms.has(code));
    return code;
  }
  function finishMatch(match: PendingMatch) {
    clearTimeout(match.timer);
    pendingMatches.delete(match);
    for (const player of match.players) pendingBySocket.delete(player.socket);
  }
  function forgetSearch(ws: WebSocket) {
    const id = searchBySocket.get(ws);
    if (id && searches.get(id)?.socket === ws) searches.delete(id);
    searchBySocket.delete(ws);
  }
  function pairWaiting() {
    while (waiting.size >= 2 && rooms.size + pendingMatches.size < (options.maxRooms ?? 1000)) {
      const entries = Array.from(waiting.entries());
      let pair: typeof entries = [];
      for (const first of entries) {
        const account = socketAccounts.get(first[0]);
        const candidates = entries.filter(
          (e) =>
            e[0] !== first[0] &&
            Boolean(socketAccounts.get(e[0])) === Boolean(account) &&
            (!account || socketAccounts.get(e[0]) !== account),
        );
        if (account)
          candidates.sort(
            (a, b) =>
              Math.abs(
                statistics.rating(socketAccounts.get(a[0])!).points -
                  statistics.rating(account).points,
              ) -
              Math.abs(
                statistics.rating(socketAccounts.get(b[0])!).points -
                  statistics.rating(account).points,
              ),
          );
        if (candidates.length) {
          pair = [first, candidates[0]];
          break;
        }
      }
      if (!pair.length) break;
      for (const [socket] of pair) waiting.delete(socket);
      const match: PendingMatch = {
        id: randomBytes(16).toString('hex'),
        players: pair.map(([socket, name]) => ({
          socket,
          name,
          accepted: false,
        })) as PendingMatch['players'],
        deadline: Date.now() + (options.matchConfirmMs ?? 15_000),
        timer: undefined as unknown as ReturnType<typeof setTimeout>,
      };
      match.timer = setTimeout(() => {
        finishMatch(match);
        for (const player of match.players) {
          if (player.socket.readyState !== WebSocket.OPEN) continue;
          if (player.accepted) {
            waiting.set(player.socket, player.name);
            send(player.socket, { type: 'queue', status: 'searching' });
          } else {
            forgetSearch(player.socket);
            send(player.socket, {
              type: 'queue_removed',
              message: 'Время подтверждения истекло.',
              reason: 'expired',
            });
          }
        }
        pairWaiting();
      }, options.matchConfirmMs ?? 15_000);
      pendingMatches.add(match);
      for (const player of match.players) pendingBySocket.set(player.socket, match);
      send(match.players[0].socket, {
        type: 'match_found',
        matchId: match.id,
        opponent: makeSeat(match.players[1].name, 2, match.players[1].socket).name,
        deadline: match.deadline,
        opponentRating: socketAccounts.get(match.players[1].socket)
          ? statistics.rating(socketAccounts.get(match.players[1].socket)!).points
          : undefined,
        rated: Boolean(
          socketAccounts.get(match.players[0].socket) &&
          statistics.canRank(
            socketAccounts.get(match.players[0].socket)!,
            socketAccounts.get(match.players[1].socket)!,
          ),
        ),
      });
      send(match.players[1].socket, {
        type: 'match_found',
        matchId: match.id,
        opponent: makeSeat(match.players[0].name, 1, match.players[0].socket).name,
        deadline: match.deadline,
        opponentRating: socketAccounts.get(match.players[0].socket)
          ? statistics.rating(socketAccounts.get(match.players[0].socket)!).points
          : undefined,
        rated: Boolean(
          socketAccounts.get(match.players[0].socket) &&
          statistics.canRank(
            socketAccounts.get(match.players[0].socket)!,
            socketAccounts.get(match.players[1].socket)!,
          ),
        ),
      });
    }
  }
  function removeFromMatch(ws: WebSocket) {
    if (waiting.delete(ws)) return;
    const match = pendingBySocket.get(ws);
    if (!match) return;
    finishMatch(match);
    const other = match.players.find((player) => player.socket !== ws)!;
    if (other.socket.readyState === WebSocket.OPEN) {
      waiting.set(other.socket, other.name);
      send(other.socket, { type: 'queue', status: 'searching' });
    }
    pairWaiting();
  }
  function attach(ws: WebSocket, room: Room, player: Player) {
    memberships.set(ws, { room, player });
    const searchId = searchBySocket.get(ws);
    const search = searchId ? searches.get(searchId) : undefined;
    if (search?.socket === ws) search.seat = { room, player };
    const seat = room.seats[player - 1]!;
    seat.socket = ws;
    seat.disconnectedAt = null;
    room.lastActivity = Date.now();
    send(ws, {
      type: 'session',
      code: room.code,
      token: seat.token,
      player,
      snapshot: snapshot(room),
    });
    broadcast(room);
  }
  function handle(ws: WebSocket, command: ClientCommand) {
    const membership = memberships.get(ws);
    if (command.type === 'quick_find') {
      const account = socketAccounts.get(ws);
      const saved = command.searchId ? searches.get(command.searchId) : undefined;
      if (saved) {
        if (saved.account !== (account ?? null)) {
          error(ws, 'INVALID_SESSION', 'Войдите в аккаунт, с которого начали поиск.');
          return;
        }
        if (membership || waiting.has(ws) || pendingBySocket.has(ws)) {
          error(ws, 'ALREADY_MATCHING', 'Вы уже участвуете в игре или поиске.');
          return;
        }
        if (
          !saved.seat &&
          account &&
          ([...waiting.keys(), ...pendingBySocket.keys()].some(
            (socket) => socket !== saved.socket && socketAccounts.get(socket) === account,
          ) ||
            [...rooms.values()].some(
              (room) =>
                room.ranking?.rated &&
                room.game.status === 'playing' &&
                room.seats.some((seat) => seat?.account === account),
            ))
        ) {
          error(
            ws,
            'ACCOUNT_BUSY',
            'У аккаунта уже есть поиск или рейтинговая партия. Вернитесь в прежнюю вкладку.',
          );
          return;
        }
        const previous = saved.socket;
        // Detach before matching another pair; the old connection must not rejoin or mutate a room.
        waiting.delete(previous);
        removeFromMatch(previous);
        memberships.delete(previous);
        searchBySocket.delete(previous);
        if (previous !== ws) {
          send(previous, { type: 'closed', message: 'Поиск открыт в другой вкладке.' });
          previous.close(4001, 'Search resumed elsewhere');
        }
        saved.socket = ws;
        saved.disconnectedAt = undefined;
        searchBySocket.set(ws, command.searchId!);
        socketNames.set(ws, saved.name);
        if (saved.seat) {
          const { room, player } = saved.seat;
          if (!rooms.has(room.code) || roomExpired(room, Date.now())) {
            forgetSearch(ws);
            error(ws, 'SEARCH_EXPIRED', 'Партия уже завершена. Начните новый поиск.');
            return;
          }
          room.revision++;
          attach(ws, room, player);
          return;
        }
        waiting.set(ws, saved.name);
        send(ws, { type: 'queue', status: 'searching' });
        pairWaiting();
        return;
      }
      if (
        account &&
        ([...waiting.keys(), ...pendingBySocket.keys()].some(
          (s) => socketAccounts.get(s) === account,
        ) ||
          [...rooms.values()].some(
            (r) =>
              r.ranking?.rated &&
              r.game.status === 'playing' &&
              r.seats.some((s) => s?.account === account),
          ))
      ) {
        error(
          ws,
          'ACCOUNT_BUSY',
          'У аккаунта уже есть поиск или рейтинговая партия. Вернитесь в прежнюю вкладку.',
        );
        return;
      }
      if (membership || waiting.has(ws) || pendingBySocket.has(ws)) {
        error(ws, 'ALREADY_MATCHING', 'Вы уже участвуете в игре или поиске.');
        return;
      }
      if (rooms.size + pendingMatches.size >= (options.maxRooms ?? 1000)) {
        error(ws, 'SERVER_FULL', 'Сервер заполнен. Попробуйте позже.');
        return;
      }
      if (command.searchId) {
        if (searches.size >= (options.maxConnections ?? 2000) * 2) {
          error(ws, 'SERVER_FULL', 'Сервер заполнен. Попробуйте позже.');
          return;
        }
        searches.set(command.searchId, {
          account: account ?? null,
          name: socketNames.get(ws)!,
          socket: ws,
        });
        searchBySocket.set(ws, command.searchId);
      }
      waiting.set(ws, socketNames.get(ws)!);
      send(ws, { type: 'queue', status: 'searching' });
      pairWaiting();
      return;
    }
    if (command.type === 'quick_cancel' || command.type === 'quick_decline') {
      if (membership) {
        error(ws, 'ALREADY_IN_LOBBY', 'Матч уже начался.');
        return;
      }
      if (command.type === 'quick_decline' && pendingBySocket.get(ws)?.id !== command.matchId) {
        error(ws, 'MATCH_NOT_FOUND', 'Предложение матча уже недействительно.');
        return;
      }
      removeFromMatch(ws);
      forgetSearch(ws);
      send(ws, { type: 'queue_removed', message: 'Поиск отменён.', reason: 'cancelled' });
      return;
    }
    if (command.type === 'quick_accept') {
      const match = pendingBySocket.get(ws);
      if (!match || match.id !== command.matchId || Date.now() >= match.deadline) {
        error(ws, 'MATCH_NOT_FOUND', 'Время подтверждения истекло.');
        return;
      }
      match.players.find((player) => player.socket === ws)!.accepted = true;
      if (match.players.every((player) => player.accepted)) {
        finishMatch(match);
        const players = randomInt(2) ? [...match.players].reverse() : match.players;
        const room: Room = {
          id: randomUUID(),
          code: newCode(),
          kind: 'quick',
          seats: [
            makeSeat(players[0].name, 1, players[0].socket),
            makeSeat(players[1].name, 2, players[1].socket),
          ],
          game: createGame(),
          revision: 0,
          round: 1,
          startedAt: Date.now(),
          finishedAt: null,
          rematch: [],
          lastActivity: Date.now(),
        };
        const a = room.seats[0].account,
          b = room.seats[1]!.account;
        const rated = Boolean(a && b && statistics.canRank(a, b));
        room.ranking = {
          rated,
          points: [a ? statistics.rating(a).points : 1000, b ? statistics.rating(b).points : 1000],
          reason: rated
            ? undefined
            : a && b
              ? 'Лимит: 3 рейтинговые встречи с этим соперником за 24 часа'
              : 'Гостевой матч без рейтинга',
        };
        room.turnDeadline = Date.now() + (options.ratedTurnMs ?? 90000);
        rooms.set(room.code, room);
        trackOnlineStart(room);
        attach(players[0].socket, room, 1);
        attach(players[1].socket, room, 2);
      }
      return;
    }
    if (waiting.has(ws) || pendingBySocket.has(ws)) {
      error(ws, 'ALREADY_MATCHING', 'Сначала завершите поиск игры.');
      return;
    }
    if (command.type === 'create' || command.type === 'join' || command.type === 'resume') {
      if (membership) {
        error(ws, 'ALREADY_IN_LOBBY', 'Сначала выйдите из текущего лобби.');
        return;
      }
      if (command.type === 'create') {
        if (rooms.size + pendingMatches.size >= (options.maxRooms ?? 1000)) {
          error(ws, 'SERVER_FULL', 'Сервер заполнен. Попробуйте позже.');
          return;
        }
        const code = newCode();
        const room: Room = {
          id: randomUUID(),
          code,
          kind: 'lobby',
          seats: [makeSeat(socketNames.get(ws)!, 1, ws), null],
          game: createGame(),
          revision: 0,
          round: 1,
          startedAt: null,
          finishedAt: null,
          rematch: [],
          lastActivity: Date.now(),
        };
        rooms.set(code, room);
        attach(ws, room, 1);
        return;
      }
      const room = rooms.get(command.code);
      if (room && roomExpired(room, Date.now()))
        closeRoom(room, 'Время ожидания истекло. Создайте новое лобби.');
      if (!room || !rooms.has(command.code)) {
        error(ws, 'LOBBY_NOT_FOUND', 'Лобби не найдено или время ожидания истекло.');
        return;
      }
      if (command.type === 'join') {
        if (room.seats[1]) {
          error(ws, 'LOBBY_FULL', 'В этом лобби уже два игрока.');
          return;
        }
        room.seats[1] = makeSeat(socketNames.get(ws)!, 2, ws);
        room.startedAt = Date.now();
        trackOnlineStart(room);
        room.revision++;
        attach(ws, room, 2);
        return;
      }
      const index = room.seats.findIndex(
        (seat) => seat && timingSafeEqual(Buffer.from(seat.token), Buffer.from(command.token)),
      );
      if (index < 0) {
        error(ws, 'INVALID_SESSION', 'Не удалось восстановить место в лобби.');
        return;
      }
      const previous = room.seats[index]!.socket;
      if (room.ranking?.rated && room.seats[index]!.account !== socketAccounts.get(ws)) {
        error(ws, 'INVALID_SESSION', 'Войдите в аккаунт участника этой партии.');
        return;
      }
      if (previous && previous !== ws) {
        memberships.delete(previous);
        send(previous, { type: 'closed', message: 'Игра открыта в другой вкладке.' });
        previous.close(4001, 'Session resumed elsewhere');
      }
      room.revision++;
      attach(ws, room, (index + 1) as Player);
      return;
    }
    if (!membership) {
      error(ws, 'NOT_IN_LOBBY', 'Сначала создайте лобби или присоединитесь к нему.');
      return;
    }
    const { room, player } = membership;
    if (roomExpired(room, Date.now())) {
      closeRoom(room, 'Время ожидания истекло. Создайте новое лобби.');
      return;
    }
    if (command.type === 'leave') {
      if (room.ranking?.rated && room.game.status === 'playing') {
        forfeit(room, player, 'Соперник сдался');
        memberships.delete(ws);
        room.seats[player - 1]!.socket = null;
        room.seats[player - 1]!.disconnectedAt = Date.now();
        send(ws, { type: 'closed', message: 'Вы сдались. Рейтинг обновлён.' });
        broadcast(room);
        return;
      }
      closeRoom(room, 'Игрок покинул лобби.');
      return;
    }
    if (!room.seats.every((seat) => seat?.socket?.readyState === WebSocket.OPEN)) {
      error(ws, 'WAITING_FOR_PLAYER', 'Ожидаем подключения второго игрока.');
      return;
    }
    if (command.round !== room.round) {
      error(ws, 'STALE_STATE', 'Состояние игры обновилось. Попробуйте ещё раз.');
      broadcast(room);
      return;
    }
    if (command.type === 'pause_ready') {
      const pause = room.pause;
      if (!pause?.endsAt || room.game.status !== 'playing') {
        error(ws, 'PAUSE_NOT_ACTIVE', 'Пауза уже закончилась.');
        return;
      }
      const ready = (pause.ready ??= []);
      if (!ready.includes(player)) {
        ready.push(player);
        if (ready.length === 2) finishPause(room, Date.now());
        room.revision++;
        room.lastActivity = Date.now();
      }
      broadcast(room);
      return;
    }
    if (command.type === 'pause_request' || command.type === 'pause_answer') {
      if (room.game.status !== 'playing' || !room.startedAt) {
        error(ws, 'GAME_NOT_PLAYING', 'Пауза доступна только во время партии.');
        return;
      }
      const now = Date.now();
      const pause = (room.pause ??= { used: false, totalMs: 0 });
      if (command.type === 'pause_request') {
        if (pause.used || pause.request || now < (room.pauseRequestAllowedAt ?? 0)) {
          error(
            ws,
            'PAUSE_UNAVAILABLE',
            pause.used
              ? 'Пауза в этой партии уже использована.'
              : 'Запрос паузы уже отправлен. Повторить можно через 30 секунд.',
          );
          return;
        }
        pause.request = {
          id: randomBytes(16).toString('hex'),
          by: player,
          expiresAt: now + (options.pauseRequestMs ?? 30000),
        };
        room.pauseRequestAllowedAt = now + 30000;
        schedulePause(room, pause.request.expiresAt);
      } else {
        if (
          !pause.request ||
          pause.request.id !== command.requestId ||
          (command.accept && pause.request.by === player)
        ) {
          error(ws, 'INVALID_PAUSE_REQUEST', 'Этот запрос паузы уже недоступен.');
          return;
        }
        if (command.accept) {
          pause.used = true;
          pause.startedAt = now;
          pause.ready = [];
          pause.endsAt = now + (options.pauseMs ?? 120000);
          if (room.turnDeadline) room.turnDeadline += pause.endsAt - now;
          pause.request = undefined;
          schedulePause(room, pause.endsAt);
        } else finishPause(room, now);
      }
      room.revision++;
      room.lastActivity = now;
      broadcast(room);
      return;
    }
    if (command.type === 'rematch') {
      if (room.game.status === 'playing') {
        error(ws, 'GAME_NOT_FINISHED', 'Сначала завершите текущую партию.');
        return;
      }
      if (!persistRoom(room)) {
        error(ws, 'STATS_UNAVAILABLE', 'Результат ещё сохраняется. Повторите запрос реванша.');
        return;
      }
      if (!room.rematch.includes(player)) {
        room.rematch.push(player);
        room.revision++;
      }
      if (room.rematch.length === 2) {
        room.round++;
        room.game = createGame(room.round % 2 === 1 ? 1 : 2);
        room.revision++;
        room.rematch = [];
        room.startedAt = Date.now();
        room.finishedAt = null;
        finishPause(room, Date.now());
        room.pause = undefined;
        room.pauseRequestAllowedAt = undefined;
        room.statisticsSaved = false;
        if (room.ranking)
          room.ranking = {
            rated: false,
            points: room.seats.map((s) =>
              s?.account ? statistics.rating(s.account).points : 1000,
            ) as [number, number],
            reason: 'Реванш без рейтинга. Для очков начните новый поиск.',
          };
        room.turnDeadline =
          room.kind === 'quick' ? Date.now() + (options.ratedTurnMs ?? 90000) : undefined;
        room.endReason = undefined;
        trackOnlineStart(room);
      }
      room.lastActivity = Date.now();
      broadcast(room);
      return;
    }
    if (room.pause?.endsAt) {
      error(ws, 'GAME_PAUSED', 'Партия на паузе.');
      return;
    }
    if (command.revision !== room.revision) {
      error(ws, 'STALE_STATE', 'Состояние игры обновилось. Попробуйте ещё раз.');
      broadcast(room);
      return;
    }
    if (room.game.currentPlayer !== player) {
      error(ws, 'NOT_YOUR_TURN', 'Сейчас ход соперника.');
      return;
    }
    const result = makeMove(room.game, command.x, command.y);
    if (!result.valid) {
      error(
        ws,
        'INVALID_MOVE',
        room.game.status === 'playing' ? 'Этот столбец заполнен.' : 'Партия уже завершена.',
      );
      return;
    }
    room.game = result.state;
    room.revision++;
    room.lastActivity = Date.now();
    if (room.kind === 'quick')
      room.turnDeadline =
        room.game.status === 'playing' ? Date.now() + (options.ratedTurnMs ?? 90000) : undefined;
    if (room.game.status !== 'playing') {
      finishPause(room, Date.now());
      room.finishedAt = Date.now();
      persistRoom(room);
    }
    broadcast(room);
  }

  wss.on('connection', (ws, request) => {
    socketAccounts.set(ws, auth.username(request.headers.cookie));
    socketNames.set(ws, auth.identity(request.headers.cookie) ?? guestName());
    alive.add(ws);
    let windowStarted = Date.now();
    let messages = 0;
    ws.on('error', () => {
      /* The close event handles lost connections. */
    });
    ws.on('pong', () => alive.add(ws));
    ws.on('message', (data, isBinary) => {
      const now = Date.now();
      if (now - windowStarted >= 60_000) {
        windowStarted = now;
        messages = 0;
      }
      if (++messages > (options.messagesPerMinute ?? 120)) {
        error(ws, 'RATE_LIMIT', 'Слишком много запросов. Подождите немного.');
        ws.close(4008, 'Rate limit');
        return;
      }
      const command = isBinary ? null : parseCommand(data.toString());
      if (!command) {
        error(ws, 'INVALID_MESSAGE', 'Некорректный запрос.');
        return;
      }
      handle(ws, command);
    });
    ws.on('close', () => {
      const searchId = searchBySocket.get(ws);
      const search = searchId ? searches.get(searchId) : undefined;
      if (search?.socket === ws) search.disconnectedAt = Date.now();
      removeFromMatch(ws);
      const membership = memberships.get(ws);
      if (!membership || shuttingDown) return;
      memberships.delete(ws);
      const { room, player } = membership;
      const seat = room.seats[player - 1]!;
      if (seat.socket !== ws) return;
      seat.socket = null;
      seat.disconnectedAt = Date.now();
      room.revision++;
      broadcast(room);
    });
  });
  const cleanup = setInterval(() => {
    for (const [id, search] of searches)
      if (
        (search.disconnectedAt !== undefined && Date.now() - search.disconnectedAt >= graceMs) ||
        (search.seat && !rooms.has(search.seat.room.code))
      )
        searches.delete(id);
    for (const room of rooms.values()) persistRoom(room);
    for (const [address, attempt] of authAttempts)
      if (attempt.until <= Date.now()) authAttempts.delete(address);
    for (const attempts of [telemetryAttempts, adminAttempts, mailAttempts, dailyAttempts])
      for (const [address, attempt] of attempts)
        if (attempt.until <= Date.now()) attempts.delete(address);
    for (const room of rooms.values())
      if (roomExpired(room, Date.now()))
        closeRoom(room, 'Время ожидания истекло. Создайте новое лобби.');
  }, options.cleanupIntervalMs ?? 5000);
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!alive.has(ws)) {
        ws.terminate();
        continue;
      }
      alive.delete(ws);
      ws.ping();
    }
  }, options.heartbeatIntervalMs ?? 30_000);
  cleanup.unref();
  heartbeat.unref();

  async function close() {
    shuttingDown = true;
    clearInterval(cleanup);
    clearInterval(heartbeat);
    for (const room of rooms.values()) {
      clearTimeout(room.pauseTimer);
      persistRoom(room);
    }
    rooms.clear();
    for (const match of pendingMatches) clearTimeout(match.timer);
    pendingMatches.clear();
    pendingBySocket.clear();
    waiting.clear();
    searches.clear();
    for (const ws of wss.clients) ws.terminate();
    await new Promise<void>((resolveClose) => wss.close(() => resolveClose()));
    if (httpServer.listening)
      await new Promise<void>((resolveClose, reject) =>
        httpServer.close((err) => (err ? reject(err) : resolveClose())),
      );
    await daily.close();
    statistics.close();
  }
  return { httpServer, wss, close };
}
