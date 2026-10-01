import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AddressInfo } from 'node:net';
import { createOnlineServer, type OnlineServerOptions } from './app';
import { createAdminPasswordHash } from './admin';
import { createGame, makeMove, serialize } from '../src/game/core';
import type { Mailer, MailMessage } from './email';
import type { ClientCommand, LobbySnapshot, ServerEvent } from '../src/network/protocol';

class Client {
  ws: WebSocket;
  events: ServerEvent[] = [];
  constructor(url: string, cookie?: string) {
    this.ws = new WebSocket(url, { headers: cookie ? { Cookie: cookie } : undefined });
    this.ws.on('message', (data) => this.events.push(JSON.parse(data.toString()) as ServerEvent));
  }
  send(command: ClientCommand) {
    this.ws.send(JSON.stringify(command));
  }
  async event<T extends ServerEvent['type']>(
    type: T,
    predicate: (event: Extract<ServerEvent, { type: T }>) => boolean = () => true,
  ): Promise<Extract<ServerEvent, { type: T }>> {
    return new Promise((resolve, reject) => {
      const check = () => {
        const index = this.events.findIndex(
          (event) => event.type === type && predicate(event as Extract<ServerEvent, { type: T }>),
        );
        if (index < 0) return;
        clearTimeout(timer);
        this.ws.off('message', check);
        resolve(this.events.splice(index, 1)[0] as Extract<ServerEvent, { type: T }>);
      };
      const timer = setTimeout(() => {
        this.ws.off('message', check);
        reject(new Error(`Timed out waiting for ${type}. Events: ${JSON.stringify(this.events)}`));
      }, 2000);
      this.ws.on('message', check);
      check();
    });
  }
  async error(code: string) {
    expect((await this.event('error')).code).toBe(code);
  }
}
const apps: ReturnType<typeof createOnlineServer>[] = [];
const clients: Client[] = [];
const dirs: string[] = [];
afterEach(async () => {
  for (const client of clients.splice(0)) client.ws.terminate();
  await Promise.all(apps.splice(0).map((app) => app.close()));
  await Promise.all(dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});
async function start(options: OnlineServerOptions = {}) {
  const app = createOnlineServer({ staticDir: null, authFile: null, statsFile: null, ...options });
  apps.push(app);
  await new Promise<void>((resolve) => app.httpServer.listen(0, '127.0.0.1', resolve));
  const port = (app.httpServer.address() as AddressInfo).port;
  const connect = async (cookie?: string) => {
    const client = new Client(`ws://127.0.0.1:${port}/online`, cookie);
    clients.push(client);
    await new Promise<void>((resolve, reject) => {
      client.ws.once('open', resolve);
      client.ws.once('error', reject);
    });
    return client;
  };
  return { ...app, connect, url: `http://127.0.0.1:${port}` };
}
describe('admin analytics HTTP API', () => {
  it('tracks real WebSocket games and rematches once for both guests', async () => {
    const server = await pair({
      adminPasswordHash: await createAdminPasswordHash('analytics-online-test-123'),
    });
    const login = await fetch(`${server.url}/admin-api/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'admin', password: 'analytics-online-test-123' }),
    });
    const adminCookie = login.headers.get('set-cookie')!.split(';')[0];
    let snapshot = server.guestSession.snapshot;
    const moves = [
      [0, 0],
      [4, 4],
      [1, 0],
      [4, 3],
      [2, 0],
      [4, 2],
      [3, 0],
    ];
    for (let i = 0; i < moves.length; i++) {
      move(i % 2 === 0 ? server.host : server.guest, snapshot, ...(moves[i] as [number, number]));
      snapshot = await state(server.host, i + 1);
    }
    const read = async () =>
      (
        await fetch(`${server.url}/admin-api/analytics`, { headers: { Cookie: adminCookie } })
      ).json();
    const completed = await read();
    expect(completed.summary).toMatchObject({ started: 1, completed: 1, guestPlayers: 2 });
    server.host.send({ type: 'rematch', round: 1 });
    server.guest.send({ type: 'rematch', round: 1 });
    await server.host.event('state', (event) => event.snapshot.round === 2);
    const rematch = await read();
    expect(rematch.summary).toMatchObject({
      started: 2,
      completed: 1,
      unfinished: 1,
      guestPlayers: 2,
    });
  });
  it('protects the dashboard and collects guest and account events without duplicates', async () => {
    const server = await start({
      adminPasswordHash: await createAdminPasswordHash('analytics-test-password'),
    });
    const post = (path: string, body: object, cookie?: string, origin?: string) =>
      fetch(`${server.url}${path}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(cookie ? { Cookie: cookie } : {}),
          ...(origin ? { Origin: origin } : {}),
        },
        body: JSON.stringify(body),
      });
    expect((await fetch(`${server.url}/admin-api/analytics`)).status).toBe(401);
    const login = await post('/admin-api/login', {
      username: 'admin',
      password: 'analytics-test-password',
    });
    const adminCookie = login.headers.get('set-cookie')!.split(';')[0];
    const account = await post('/auth/register', {
      username: 'AnalyticsPlayer',
      password: 'test-password-123',
    });
    const cookie = account.headers.get('set-cookie')!.split(';')[0];
    const base = { session: 'browser-session-01', visitor: 'browser-visitor-01' };
    const visit = { ...base, type: 'visit', device: 'desktop', browser: 'Chrome' };
    expect((await post('/telemetry', visit, cookie)).status).toBe(204);
    expect((await post('/telemetry', visit, cookie)).status).toBe(204);
    expect((await post('/telemetry', visit, cookie, 'https://other.example')).status).toBe(403);
    expect(
      (
        await post(
          '/telemetry',
          {
            ...base,
            type: 'game_start',
            id: 'local-api-match01',
            mode: 'ai',
            difficulty: 'medium',
            owner: 'ForgedPlayer',
          },
          cookie,
        )
      ).status,
    ).toBe(204);
    let game = createGame();
    for (const [x, y] of [
      [0, 0],
      [4, 4],
      [1, 0],
      [4, 3],
      [2, 0],
      [4, 2],
      [3, 0],
    ]) {
      const result = makeMove(game, x, y);
      if (!result.valid) throw new Error(result.reason);
      game = result.state;
    }
    const end = {
      ...base,
      type: 'game_end',
      id: 'local-api-match01',
      game: serialize(game),
      elapsed: 30,
    };
    expect((await post('/telemetry', end, cookie)).status).toBe(204);
    expect((await post('/telemetry', end, cookie)).status).toBe(204);
    const dashboard = await (
      await fetch(`${server.url}/admin-api/analytics`, { headers: { Cookie: adminCookie } })
    ).json();
    expect(dashboard.summary).toMatchObject({
      sessions: 1,
      visitors: 1,
      started: 1,
      completed: 1,
      registeredPlayers: 0,
    });
    expect(dashboard.players).toEqual([]);
    expect(dashboard.bots[0]).toMatchObject({ difficulty: 'medium', wins: 1 });
    expect(
      (
        await fetch(`${server.url}/admin-api/analytics?mode=invalid`, {
          headers: { Cookie: adminCookie },
        })
      ).status,
    ).toBe(400);
    expect(
      (
        await post(
          '/telemetry',
          { ...base, type: 'game_start', id: 'spoof-online-01', mode: 'ranked' },
          cookie,
        )
      ).status,
    ).toBe(400);
  });
});
async function pair(options?: OnlineServerOptions) {
  const server = await start(options);
  const host = await server.connect();
  host.send({ type: 'create', name: '  Alice  ' });
  const hostSession = await host.event('session');
  const guest = await server.connect();
  guest.send({ type: 'join', name: 'Bob', code: hostSession.code.toLowerCase() });
  const guestSession = await guest.event('session');
  return { ...server, host, guest, hostSession, guestSession };
}
function move(client: Client, snapshot: LobbySnapshot, x = 0, y = 0) {
  client.send({ type: 'move', x, y, revision: snapshot.revision, round: snapshot.round });
}
async function state(client: Client, moves: number) {
  return (await client.event('state', (event) => event.snapshot.game.history.length === moves))
    .snapshot;
}

async function rankedPair(options?: OnlineServerOptions) {
  const server = await start(options);
  const cookies: string[] = [];
  for (const username of ['RankAlice', 'RankBob']) {
    const response = await fetch(`${server.url}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password: 'rank-test-password' }),
    });
    expect(response.status).toBe(200);
    cookies.push(response.headers.get('set-cookie')!.split(';')[0]);
  }
  const a = await server.connect(cookies[0]),
    b = await server.connect(cookies[1]);
  const anonymous = await server.connect();
  anonymous.send({ type: 'quick_find', name: 'Guest' });
  await anonymous.event('queue');
  a.send({ type: 'quick_find', name: 'Fake' });
  await a.event('queue');
  const duplicate = await server.connect(cookies[0]);
  duplicate.send({ type: 'quick_find', name: 'Fake' });
  await duplicate.error('ACCOUNT_BUSY');
  b.send({ type: 'quick_find', name: 'Fake' });
  const offerA = await a.event('match_found'),
    offerB = await b.event('match_found');
  expect(offerA).toMatchObject({ opponent: 'RankBob', opponentRating: 1000, rated: true });
  expect(anonymous.events.some((e) => e.type === 'match_found')).toBe(false);
  a.send({ type: 'quick_accept', matchId: offerA.matchId });
  b.send({ type: 'quick_accept', matchId: offerB.matchId });
  const sa = await a.event('session'),
    sb = await b.event('session');
  const read = (index: number) =>
    fetch(`${server.url}/auth/history`, { headers: { Cookie: cookies[index] } }).then((r) =>
      r.json(),
    );
  return { ...server, a, b, sa, sb, cookies, read };
}

describe('resumable quick search', () => {
  it('replaces a suspended search without duplicates and keeps the guest identity', async () => {
    const { connect } = await start();
    const first = await connect();
    const command = { type: 'quick_find', name: 'ignored', searchId: 'a'.repeat(32) } as const;
    first.send(command);
    await first.event('queue');
    const restored = await connect();
    restored.send(command);
    await restored.event('queue');
    await first.event('closed');
    const other = await connect();
    other.send({ type: 'quick_find', name: 'other' });
    const match = await restored.event('match_found');
    expect((await other.event('match_found')).matchId).toBe(match.matchId);
    restored.send({ type: 'quick_accept', matchId: match.matchId });
    other.send({ type: 'quick_accept', matchId: match.matchId });
    const session = await restored.event('session');
    await other.event('session');
    // Recover the same room if the OS lost the session acknowledgment after both accepted.
    restored.ws.terminate();
    const afterAcceptance = await connect();
    afterAcceptance.send(command);
    const recovered = await afterAcceptance.event('session');
    expect(recovered.code).toBe(session.code);
    expect(recovered.token).toBe(session.token);
    expect(recovered.snapshot.players[session.player - 1]?.name).toBe(
      session.snapshot.players[session.player - 1]?.name,
    );
  });

  it('requeues a disconnected pending player and requires fresh confirmation', async () => {
    const { connect } = await start();
    const a = await connect(),
      b = await connect();
    const command = { type: 'quick_find', name: 'A', searchId: 'b'.repeat(32) } as const;
    a.send(command);
    await a.event('queue');
    b.send({ type: 'quick_find', name: 'B' });
    await b.event('queue');
    const offer = await a.event('match_found');
    await b.event('match_found');
    a.send({ type: 'quick_accept', matchId: offer.matchId });
    a.ws.terminate();
    await b.event('queue');
    const restored = await connect();
    restored.send(command);
    await restored.event('queue');
    const next = await restored.event('match_found');
    expect(next.matchId).not.toBe(offer.matchId);
    restored.send({ type: 'quick_accept', matchId: offer.matchId });
    await restored.error('MATCH_NOT_FOUND');
    b.send({ type: 'quick_accept', matchId: next.matchId });
    restored.send({ type: 'quick_accept', matchId: next.matchId });
    expect((await restored.event('session')).snapshot.game.history).toHaveLength(0);
  });

  it('binds search recovery to its account', async () => {
    const { connect, url } = await start();
    const response = await fetch(`${url}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'SearchOwner', password: 'search-test-pass' }),
    });
    const cookie = response.headers.get('set-cookie')!.split(';')[0];
    const owner = await connect(cookie);
    const command = { type: 'quick_find', name: 'ignored', searchId: 'c'.repeat(32) } as const;
    owner.send(command);
    await owner.event('queue');
    const guest = await connect();
    guest.send(command);
    await guest.error('INVALID_SESSION');
    const restored = await connect(cookie);
    restored.send(command);
    await restored.event('queue');
  });
});

describe('ranked quick matches', () => {
  it('resumes early only after both players are ready and restores the remaining turn time', async () => {
    const { a, b, sa } = await rankedPair({
      ratedTurnMs: 800,
      pauseMs: 5000,
      cleanupIntervalMs: 10,
    });
    a.send({ type: 'pause_request', round: 1 });
    const request = (await b.event('state', (e) => Boolean(e.snapshot.pause?.request))).snapshot
      .pause!.request!;
    b.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: true });
    await a.event('state', (e) => Boolean(e.snapshot.pause?.endsAt));
    a.send({ type: 'pause_ready', round: 1 });
    const first = (await a.event('state', (e) => e.snapshot.pause?.ready?.length === 1)).snapshot;
    a.send({ type: 'pause_ready', round: 1 });
    const duplicate = (await a.event('state', (e) => e.snapshot.pause?.ready?.length === 1))
      .snapshot;
    expect(duplicate).toEqual(first);
    await new Promise((resolve) => setTimeout(resolve, 30));
    b.send({ type: 'pause_ready', round: 1 });
    const resumed = (
      await b.event('state', (e) => Boolean(e.snapshot.pause?.totalMs) && !e.snapshot.pause?.endsAt)
    ).snapshot;
    expect(resumed.pause?.totalMs).toBeLessThan(5000);
    expect(resumed.pause?.ready).toBeUndefined();
    expect(resumed.turnDeadline).toBe(sa.snapshot.turnDeadline! + resumed.pause!.totalMs);
    expect(resumed.game.status).toBe('playing');
    const ended = (await a.event('state', (e) => e.snapshot.game.status === 'won')).snapshot;
    expect(ended.endReason).toBe('Время хода истекло');
  });
  it('freezes the rated turn and disconnect grace during an agreed pause', async () => {
    const { a, b, sa, connect, cookies } = await rankedPair({
      ratedTurnMs: 500,
      pauseMs: 650,
      disconnectGraceMs: 400,
      cleanupIntervalMs: 10,
    });
    a.send({ type: 'pause_request', round: 1 });
    const request = (await b.event('state', (e) => Boolean(e.snapshot.pause?.request))).snapshot
      .pause!.request!;
    b.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: true });
    const paused = (await b.event('state', (e) => Boolean(e.snapshot.pause?.endsAt))).snapshot;
    expect(paused.turnDeadline).toBe(sa.snapshot.turnDeadline! + 650);
    a.ws.terminate();
    await new Promise((resolve) => setTimeout(resolve, 550));
    const restored = await connect(cookies[0]);
    restored.send({ type: 'resume', code: sa.code, token: sa.token });
    const session = await restored.event('session');
    expect(session.snapshot.game.status).toBe('playing');
    expect(session.snapshot.pause?.endsAt).toBe(paused.pause?.endsAt);
    const resumed = (await restored.event('state', (e) => e.snapshot.pause?.totalMs === 650))
      .snapshot;
    expect(resumed.game.status).toBe('playing');
    expect(resumed.pause?.endsAt).toBeUndefined();
    const ended = (await restored.event('state', (e) => e.snapshot.game.status === 'won')).snapshot;
    expect(ended.endReason).toBe('Время хода истекло');
  });
  it('rates a real win once and makes mutual rematches casual', async () => {
    const { a, b, sa, read } = await rankedPair();
    let snapshot = sa.snapshot;
    const first = sa.player === 1 ? a : b,
      second = sa.player === 1 ? b : a;
    for (const [i, [x, y]] of [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [3, 0],
    ].entries()) {
      move(i % 2 ? second : first, snapshot, x, y);
      snapshot = await state(a, i + 1);
    }
    expect(snapshot.ranking?.changes).toEqual([16, -16]);
    expect((await read(sa.player === 1 ? 0 : 1)).rating).toEqual({ points: 1016, games: 1 });
    a.send({ type: 'rematch', round: 1 });
    b.send({ type: 'rematch', round: 1 });
    const next = (await a.event('state', (e) => e.snapshot.round === 2)).snapshot;
    expect(next.ranking?.rated).toBe(false);
    expect(next.turnDeadline).toBeGreaterThan(Date.now() + 88000);
    a.send({ type: 'leave' });
    await b.event('closed');
    expect((await read(0)).rating.games).toBe(1);
  });
  it('keeps the turn clock in an unrated rematch without changing rating again', async () => {
    const { a, b, sa, read } = await rankedPair({ ratedTurnMs: 1000, cleanupIntervalMs: 10 });
    let snapshot = sa.snapshot;
    const first = sa.player === 1 ? a : b,
      second = sa.player === 1 ? b : a;
    for (const [i, [x, y]] of [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [3, 0],
    ].entries()) {
      move(i % 2 ? second : first, snapshot, x, y);
      snapshot = await state(a, i + 1);
    }
    a.send({ type: 'rematch', round: 1 });
    b.send({ type: 'rematch', round: 1 });
    const rematch = (await a.event('state', (e) => e.snapshot.round === 2)).snapshot;
    expect(rematch.ranking?.rated).toBe(false);
    expect(rematch.turnDeadline).toBeGreaterThan(Date.now());
    await new Promise((resolve) => setTimeout(resolve, 30));
    const current = rematch.game.currentPlayer === sa.player ? a : b;
    move(current, rematch, 4, 4);
    const afterMove = (
      await a.event('state', (e) => e.snapshot.round === 2 && e.snapshot.game.history.length === 1)
    ).snapshot;
    expect(afterMove.turnDeadline).toBeGreaterThan(rematch.turnDeadline!);
    const ended = (
      await b.event('state', (e) => e.snapshot.round === 2 && e.snapshot.game.status === 'won')
    ).snapshot;
    expect(ended.endReason).toBe('Время хода истекло');
    expect(ended.game.winner).toBe(afterMove.game.currentPlayer === 1 ? 2 : 1);
    expect((await read(0)).rating.games).toBe(1);
    expect((await read(1)).rating.games).toBe(1);
  });
  it('counts explicit exit as defeat and blocks a second ranked game in another tab', async () => {
    const { a, b, connect, cookies, read } = await rankedPair();
    const duplicate = await connect(cookies[0]);
    duplicate.send({ type: 'quick_find', name: 'Fake' });
    await duplicate.error('ACCOUNT_BUSY');
    a.send({ type: 'leave' });
    const ended = (await b.event('state', (e) => e.snapshot.game.status === 'won')).snapshot;
    expect(ended.endReason).toContain('сдался');
    expect((await read(0)).rating.points).toBe(984);
    expect((await read(1)).rating.points).toBe(1016);
    expect((await read(0)).matches[0]).toMatchObject({
      endReason: 'Соперник сдался',
      ratingChange: -16,
    });
  });
  it('does not reset the turn deadline on reconnect and rejects another account resuming a ranked seat', async () => {
    const { a, b, sa, connect, cookies, read } = await rankedPair({
      ratedTurnMs: 250,
      cleanupIntervalMs: 10,
    });
    const impostor = await connect(cookies[1]);
    impostor.send({ type: 'resume', code: sa.code, token: sa.token });
    await impostor.error('INVALID_SESSION');
    a.ws.terminate();
    const restored = await connect(cookies[0]);
    restored.send({ type: 'resume', code: sa.code, token: sa.token });
    const session = await restored.event('session');
    expect(session.snapshot.turnDeadline).toBe(sa.snapshot.turnDeadline);
    const ended = (await b.event('state', (e) => e.snapshot.game.status === 'won')).snapshot;
    expect(ended.game.winner).toBe(2);
    expect(ended.endReason).toBe('Время хода истекло');
    expect((await read(0)).rating.games).toBe(1);
  });
  it('records disconnect forfeits even when the loser never returns', async () => {
    const { a, b, read } = await rankedPair({ disconnectGraceMs: 40, cleanupIntervalMs: 10 });
    a.ws.terminate();
    const ended = (await b.event('state', (e) => e.snapshot.game.status === 'won')).snapshot;
    expect(ended.endReason).toBe('Поражение за отключение');
    expect((await read(0)).rating.points).toBe(984);
    expect((await read(1)).rating.points).toBe(1016);
  });
});

describe('online lobby server over real WebSockets', () => {
  it('stores account level progress across devices, protects ownership and requires login', async () => {
    const { url } = await start();
    const post = (path: string, data: object, cookie?: string) =>
      fetch(`${url}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
        body: JSON.stringify(data),
      });
    const registered = await post('/auth/register', {
      username: 'LevelPlayer',
      password: 'password-123',
    });
    const cookie = registered.headers.get('set-cookie')!.split(';')[0];
    expect((await fetch(`${url}/auth/levels`)).status).toBe(401);
    expect((await post('/auth/levels', { owner: 'Other', best: { 1: 2 } }, cookie)).status).toBe(
      403,
    );
    expect(
      (await post('/auth/levels', { owner: 'LevelPlayer', best: { 41: 2 } }, cookie)).status,
    ).toBe(400);
    expect(
      (await post('/auth/levels', { owner: 'LevelPlayer', best: { 1: 5 } }, cookie)).status,
    ).toBe(200);
    const login = await post('/auth/login', { username: 'LevelPlayer', password: 'password-123' });
    const secondCookie = login.headers.get('set-cookie')!.split(';')[0];
    expect(
      await (await fetch(`${url}/auth/levels`, { headers: { Cookie: secondCookie } })).json(),
    ).toEqual({ username: 'LevelPlayer', best: { 1: 5 } });
    await post('/auth/levels', { owner: 'LevelPlayer', best: { 1: 8, 2: 3 } }, secondCookie);
    expect(
      await (await fetch(`${url}/auth/levels`, { headers: { Cookie: cookie } })).json(),
    ).toEqual({ username: 'LevelPlayer', best: { 1: 5, 2: 3 } });
  });
  it('exposes only public leaderboard fields to guests and rejects writes', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-leaderboard-'));
    dirs.push(dir);
    await writeFile(
      join(dir, 'accounts.json'),
      JSON.stringify({
        accounts: {
          alice: {
            username: 'Alice',
            salt: 'secret',
            hash: 'secret',
            email: 'private@example.com',
            emailVerified: true,
          },
          bob: { username: 'Bob', salt: 'secret', hash: 'secret' },
          blocked: { username: 'Blocked', disabled: true },
          pending: { username: 'Pending', email: 'pending@example.com', emailVerified: false },
        },
        sessions: {},
      }),
    );
    const { url } = await start({ authFile: join(dir, 'accounts.json') });
    const response = await fetch(`${url}/auth/leaderboard`);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      players: [
        { rank: 1, username: 'Alice', elo: 1000, games: 0 },
        { rank: 2, username: 'Bob', elo: 1000, games: 0 },
      ],
    });
    expect((await fetch(`${url}/auth/leaderboard`, { method: 'POST' })).status).toBe(405);
  });
  it('protects the admin panel and lets an administrator manage accounts safely', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-admin-'));
    dirs.push(dir);
    const passwordHash = await createAdminPasswordHash('control-password-123');
    const { url, connect } = await start({
      authFile: join(dir, 'accounts.json'),
      statsFile: join(dir, 'statistics.sqlite'),
      adminPasswordHash: passwordHash,
    });
    const post = (path: string, data: object, cookie?: string, method = 'POST') =>
      fetch(`${url}${path}`, {
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(cookie ? { Cookie: cookie } : {}),
        },
        body: JSON.stringify(data),
      });
    const registered = await post('/auth/register', {
      username: 'ManagedPlayer',
      password: 'player-password-123',
    });
    const playerCookie = registered.headers.get('set-cookie')!.split(';')[0];
    expect((await fetch(`${url}/admin-api/accounts`)).status).toBe(401);
    expect(
      (
        await post('/admin-api/login', {
          username: 'admin',
          password: 'wrong-password',
        })
      ).status,
    ).toBe(401);
    const loggedIn = await post('/admin-api/login', {
      username: 'admin',
      password: 'control-password-123',
    });
    expect(loggedIn.status).toBe(200);
    const adminCookie = loggedIn.headers.get('set-cookie')!.split(';')[0];
    const initial = await (
      await fetch(`${url}/admin-api/accounts`, { headers: { Cookie: adminCookie } })
    ).json();
    expect(initial.accounts[0]).toMatchObject({
      username: 'ManagedPlayer',
      email: '',
      disabled: false,
      rating: { points: 1000, games: 0 },
    });
    expect(initial.accounts[0].createdAt).toEqual(expect.any(Number));
    const changed = await post(
      '/admin-api/accounts',
      {
        originalUsername: 'ManagedPlayer',
        username: 'RenamedPlayer',
        email: 'renamed@example.com',
        emailVerified: true,
        disabled: false,
        rating: 1425,
      },
      adminCookie,
      'PATCH',
    );
    expect(await changed.json()).toMatchObject({
      account: {
        username: 'RenamedPlayer',
        email: 'renamed@example.com',
        emailVerified: true,
        rating: { points: 1425, games: 0 },
      },
    });
    expect(
      (await (await fetch(`${url}/auth/me`, { headers: { Cookie: playerCookie } })).json())
        .authenticated,
    ).toBe(false);
    expect(
      (
        await post('/auth/login', {
          username: 'RenamedPlayer',
          password: 'player-password-123',
        })
      ).status,
    ).toBe(200);
    const reset = await post(
      '/admin-api/accounts/reset-password',
      { username: 'RenamedPlayer' },
      adminCookie,
    );
    const temporary = (await reset.json()).temporaryPassword as string;
    expect(temporary).toHaveLength(18);
    expect(
      (
        await post('/auth/login', {
          username: 'RenamedPlayer',
          password: 'player-password-123',
        })
      ).status,
    ).toBe(401);
    expect(
      (
        await post('/auth/login', {
          username: 'RenamedPlayer',
          password: temporary,
        })
      ).status,
    ).toBe(200);
    await post(
      '/admin-api/accounts',
      {
        originalUsername: 'RenamedPlayer',
        username: 'RenamedPlayer',
        email: 'renamed@example.com',
        emailVerified: true,
        disabled: true,
        rating: 1425,
      },
      adminCookie,
      'PATCH',
    );
    expect(
      (
        await post('/auth/login', {
          username: 'RenamedPlayer',
          password: temporary,
        })
      ).status,
    ).toBe(403);
    await post(
      '/admin-api/accounts',
      {
        originalUsername: 'RenamedPlayer',
        username: 'RenamedPlayer',
        email: 'renamed@example.com',
        emailVerified: true,
        disabled: false,
        rating: 1425,
      },
      adminCookie,
      'PATCH',
    );
    const activeLogin = await post('/auth/login', {
      username: 'RenamedPlayer',
      password: temporary,
    });
    const activeCookie = activeLogin.headers.get('set-cookie')!.split(';')[0];
    const managed = await connect(activeCookie);
    managed.send({ type: 'create', name: 'ignored' });
    const managedSession = await managed.event('session');
    const opponent = await connect();
    opponent.send({ type: 'join', code: managedSession.code, name: 'Opponent' });
    await opponent.event('session');
    expect(
      (
        await post(
          '/admin-api/accounts',
          { username: 'RenamedPlayer', confirmation: 'wrong' },
          adminCookie,
          'DELETE',
        )
      ).status,
    ).toBe(400);
    const removed = await post(
      '/admin-api/accounts',
      { username: 'RenamedPlayer', confirmation: 'RenamedPlayer' },
      adminCookie,
      'DELETE',
    );
    expect(await removed.json()).toEqual({ deleted: true, username: 'RenamedPlayer' });
    expect((await managed.event('closed')).message).toContain('аккаунт удалён');
    expect((await opponent.event('closed')).message).toContain('соперника удалён');
    const afterDelete = await (
      await fetch(`${url}/admin-api/accounts?q=RenamedPlayer`, {
        headers: { Cookie: adminCookie },
      })
    ).json();
    expect(afterDelete).toMatchObject({ accounts: [], total: 0 });
    expect(
      (
        await post('/auth/login', {
          username: 'RenamedPlayer',
          password: temporary,
        })
      ).status,
    ).toBe(401);
    expect(
      (
        await post('/auth/register', {
          username: 'RenamedPlayer',
          password: 'fresh-password-123',
        })
      ).status,
    ).toBe(200);
    const recreated = await (
      await fetch(`${url}/admin-api/accounts?q=RenamedPlayer`, {
        headers: { Cookie: adminCookie },
      })
    ).json();
    expect(recreated.accounts[0].rating).toEqual({ points: 1000, games: 0 });
  });

  it('serves tutorial videos with MIME and byte ranges for mobile playback and seeking', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-video-'));
    dirs.push(dir);
    await writeFile(join(dir, 'lesson.mp4'), '0123456789');
    const { url } = await start({ staticDir: dir });
    const head = await fetch(`${url}/lesson.mp4`, { method: 'HEAD' });
    expect(head.headers.get('content-type')).toBe('video/mp4');
    expect(head.headers.get('content-length')).toBe('10');
    expect(head.headers.get('accept-ranges')).toBe('bytes');
    for (const [range, body, contentRange] of [
      ['bytes=0-1', '01', 'bytes 0-1/10'],
      ['bytes=8-', '89', 'bytes 8-9/10'],
      ['bytes=-3', '789', 'bytes 7-9/10'],
      ['bytes=8-999', '89', 'bytes 8-9/10'],
    ]) {
      const response = await fetch(`${url}/lesson.mp4`, { headers: { Range: range } });
      expect(response.status).toBe(206);
      expect(response.headers.get('content-range')).toBe(contentRange);
      expect(await response.text()).toBe(body);
    }
    for (const range of ['bytes=100-', 'bytes=8-2', 'bytes=-0', 'bytes=-', 'bytes=0-2,6-8'])
      expect((await fetch(`${url}/lesson.mp4`, { headers: { Range: range } })).status).toBe(416);
    expect(await (await fetch(`${url}/lesson.mp4`)).text()).toBe('0123456789');
  });
  it('requires opponent consent, blocks moves for two minutes and preserves the pause on reconnect', async () => {
    const { host, guest, hostSession, connect } = await pair();
    host.send({ type: 'pause_request', round: 1 });
    const requested = (await guest.event('state', (e) => Boolean(e.snapshot.pause?.request)))
      .snapshot;
    const request = requested.pause!.request!;
    expect(request.by).toBe(1);
    expect(requested.pause?.used).toBe(false);
    host.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: true });
    await host.error('INVALID_PAUSE_REQUEST');
    move(host, requested);
    const moved = await state(guest, 1);
    expect(moved.pause?.request?.id).toBe(request.id);
    guest.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: true });
    const paused = (await guest.event('state', (e) => Boolean(e.snapshot.pause?.endsAt))).snapshot;
    expect(paused.pause!.endsAt! - paused.pause!.startedAt!).toBe(120000);
    expect(paused.pause?.used).toBe(true);
    move(guest, paused);
    await guest.error('GAME_PAUSED');
    guest.send({ type: 'pause_request', round: 1 });
    await guest.error('PAUSE_UNAVAILABLE');
    host.ws.terminate();
    const restored = await connect();
    restored.send({ type: 'resume', code: hostSession.code, token: hostSession.token });
    expect((await restored.event('session')).snapshot.pause).toEqual(paused.pause);
    guest.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: false });
    await guest.error('INVALID_PAUSE_REQUEST');
  });

  it('preserves readiness on reconnect and requires two distinct players to resume', async () => {
    const { host, guest, hostSession, connect } = await pair();
    host.send({ type: 'pause_ready', round: 1 });
    await host.error('PAUSE_NOT_ACTIVE');
    host.send({ type: 'pause_request', round: 1 });
    const request = (await guest.event('state', (e) => Boolean(e.snapshot.pause?.request))).snapshot
      .pause!.request!;
    guest.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: true });
    await host.event('state', (e) => Boolean(e.snapshot.pause?.endsAt));
    host.send({ type: 'pause_ready', round: 1 });
    const voted = (await guest.event('state', (e) => e.snapshot.pause?.ready?.length === 1))
      .snapshot;
    expect(voted.pause?.ready).toEqual([1]);
    host.ws.terminate();
    const restored = await connect();
    restored.send({ type: 'resume', code: hostSession.code, token: hostSession.token });
    expect((await restored.event('session')).snapshot.pause).toEqual(voted.pause);
    guest.send({ type: 'pause_ready', round: 1 });
    const resumed = (
      await restored.event(
        'state',
        (e) => Boolean(e.snapshot.pause?.totalMs) && !e.snapshot.pause?.endsAt,
      )
    ).snapshot;
    expect(resumed.pause?.used).toBe(true);
    move(restored, resumed);
    await state(guest, 1);
    guest.send({ type: 'pause_request', round: 1 });
    await guest.error('PAUSE_UNAVAILABLE');
  });

  it('automatically resumes with only one ready, prevents a second pause and resets the allowance on a mutual rematch', async () => {
    const { host, guest } = await pair({ pauseMs: 60 });
    host.send({ type: 'pause_request', round: 1 });
    const request = (await guest.event('state', (e) => Boolean(e.snapshot.pause?.request))).snapshot
      .pause!.request!;
    guest.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: true });
    await host.event('state', (e) => Boolean(e.snapshot.pause?.endsAt));
    host.send({ type: 'pause_ready', round: 1 });
    let current = (await host.event('state', (e) => e.snapshot.pause?.totalMs === 60)).snapshot;
    expect(current.pause).toMatchObject({ used: true, totalMs: 60 });
    expect(current.pause?.endsAt).toBeUndefined();
    guest.send({ type: 'pause_request', round: 1 });
    await guest.error('PAUSE_UNAVAILABLE');
    for (const [i, [x, y]] of [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [3, 0],
    ].entries()) {
      move(i % 2 ? guest : host, current, x, y);
      current = await state(host, i + 1);
    }
    host.send({ type: 'pause_request', round: 1 });
    await host.error('GAME_NOT_PLAYING');
    host.send({ type: 'rematch', round: 1 });
    guest.send({ type: 'rematch', round: 1 });
    const next = (await host.event('state', (e) => e.snapshot.round === 2)).snapshot;
    expect(next.pause).toBeUndefined();
    host.send({ type: 'pause_request', round: 1 });
    await host.error('STALE_STATE');
    guest.send({ type: 'pause_request', round: 2 });
    await host.event('state', (e) => e.snapshot.round === 2 && e.snapshot.pause?.request?.by === 2);
  });

  it('declines, cancels and expires requests without consuming the pause', async () => {
    for (const answer of ['decline', 'cancel', 'expire'] as const) {
      const { host, guest } = await pair({ pauseRequestMs: 100 });
      host.send({ type: 'pause_request', round: 1 });
      const request = (await guest.event('state', (e) => Boolean(e.snapshot.pause?.request)))
        .snapshot.pause!.request!;
      if (answer !== 'expire')
        (answer === 'cancel' ? host : guest).send({
          type: 'pause_answer',
          round: 1,
          requestId: request.id,
          accept: false,
        });
      const cleared = (
        await guest.event('state', (e) => Boolean(e.snapshot.pause) && !e.snapshot.pause?.request)
      ).snapshot;
      expect(cleared.pause).toEqual({ used: false, totalMs: 0 });
      guest.send({ type: 'pause_answer', round: 1, requestId: request.id, accept: true });
      await guest.error('INVALID_PAUSE_REQUEST');
      move(host, cleared);
      await state(guest, 1);
    }
  });
  it('records online results for both accounts once and keeps history private', async () => {
    const { url, connect } = await start();
    const register = async (username: string) => {
      const response = await fetch(`${url}/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password: 'test-password-123' }),
      });
      expect(response.status).toBe(200);
      return response.headers.get('set-cookie')!.split(';')[0];
    };
    const a = await register('Alice');
    const b = await register('Bob');
    const outsider = await register('Other');
    const get = (cookie: string) =>
      fetch(`${url}/auth/history`, { headers: { Cookie: cookie } }).then((r) => r.json());
    expect((await fetch(`${url}/auth/history`)).status).toBe(401);
    const host = await connect(a);
    host.send({ type: 'create', name: 'Fake' });
    const session = await host.event('session');
    const guest = await connect(b);
    guest.send({ type: 'join', name: 'Fake', code: session.code });
    await guest.event('session');
    let snapshot = await state(host, 0);
    if (!snapshot.players[1]) snapshot = await state(host, 0);
    for (const [i, [x, y]] of [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [3, 0],
    ].entries()) {
      move(i % 2 ? guest : host, snapshot, x, y);
      snapshot = await state(host, i + 1);
    }
    const result = await get(a);
    expect(result.statistics).toEqual({ total: 1, wins: 1, losses: 0, draws: 0 });
    expect((await get(b)).statistics).toEqual({ total: 1, wins: 0, losses: 1, draws: 0 });
    expect((await get(outsider)).matches).toEqual([]);
    const post = (cookie: string, path: string, body: object) =>
      fetch(`${url}/auth/history${path}`, {
        method: 'POST',
        headers: { Cookie: cookie, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
    expect(
      (
        await post(outsider, '/rename', {
          owner: 'Other',
          id: result.matches[0].id,
          title: 'Stolen',
        })
      ).status,
    ).toBe(404);
    expect((await post(a, '', { ...result.matches[0], owner: 'Alice' })).status).toBe(400);
    expect((await post(a, '/remove', { owner: 'Bob', id: result.matches[0].id })).status).toBe(403);
    host.send({ type: 'rematch', round: snapshot.round });
    guest.send({ type: 'rematch', round: snapshot.round });
    snapshot = (await host.event('state', (e) => e.snapshot.round === 2)).snapshot;
    expect((await get(a)).statistics.total).toBe(1);
    expect(snapshot.game.currentPlayer).toBe(2);
    for (const [i, [x, y]] of [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [3, 0],
    ].entries()) {
      move(i % 2 ? host : guest, snapshot, x, y);
      snapshot = (
        await host.event(
          'state',
          (e) => e.snapshot.round === 2 && e.snapshot.game.history.length === i + 1,
        )
      ).snapshot;
    }
    expect((await get(a)).statistics).toEqual({ total: 2, wins: 1, losses: 1, draws: 0 });
    expect((await get(b)).statistics).toEqual({ total: 2, wins: 1, losses: 1, draws: 0 });
  });

  it('keeps a guest name across requests and ignores spoofed online names', async () => {
    const { url, connect } = await start();
    const response = await fetch(`${url}/auth/me`);
    const identity = (await response.json()) as { guestName: string; authenticated: boolean };
    const cookie = response.headers.get('set-cookie')!.split(';')[0];
    expect(identity.authenticated).toBe(false);
    expect(identity.guestName).toMatch(/^Гость_\d{6}$/);
    expect(
      (await (await fetch(`${url}/auth/me`, { headers: { Cookie: cookie } })).json()).guestName,
    ).toBe(identity.guestName);
    const client = await connect(cookie);
    client.send({ type: 'create', name: 'Admin' });
    expect((await client.event('session')).snapshot.players[0].name).toBe(identity.guestName);
  });

  it('registers unique accounts, persists password hashes, and uses the account name online', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-auth-'));
    dirs.push(dir);
    const authFile = join(dir, 'accounts.json');
    const server = await start({ authFile });
    const post = (url: string, path: string, username: string, password: string, cookie?: string) =>
      fetch(`${url}/auth/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
        body: JSON.stringify({ username, password }),
      });
    const russian = await post(server.url, 'register', 'Алексей_1', 'strong-pass-123');
    expect(russian.status).toBe(400);
    expect((await russian.json()).error).toContain('английских букв');
    const registered = await post(server.url, 'register', 'Alexey_1', 'strong-pass-123');
    expect(registered.status).toBe(200);
    const cookie = registered.headers.get('set-cookie')!.split(';')[0];
    expect((await registered.json()).username).toBe('Alexey_1');
    expect(await (await post(server.url, 'register', 'ALEXEY_1', 'other-pass-123')).status).toBe(
      409,
    );
    expect(await (await post(server.url, 'register', 'constructor', 'other-pass-123')).status).toBe(
      200,
    );
    expect(await (await post(server.url, 'login', 'Alexey_1', 'wrong-pass')).status).toBe(401);
    const client = await server.connect(cookie);
    client.send({ type: 'create', name: 'FakeName' });
    expect((await client.event('session')).snapshot.players[0].name).toBe('Alexey_1');
    const database = await (await import('node:fs/promises')).readFile(authFile, 'utf8');
    expect(database).not.toContain('strong-pass-123');
    const restored = await start({ authFile });
    const login = await post(restored.url, 'login', 'alexey_1', 'strong-pass-123');
    expect(login.status).toBe(200);
    const logout = await fetch(`${restored.url}/auth/logout`, {
      method: 'POST',
      headers: { Cookie: login.headers.get('set-cookie')!.split(';')[0] },
    });
    expect((await logout.json()).guestName).toMatch(/^Гость_\d{6}$/);
  });

  it('shows account profile details and changes a signed-in password securely', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-password-change-'));
    dirs.push(dir);
    const authFile = join(dir, 'accounts.json');
    const server = await start({ authFile });
    const post = (path: string, body: object, cookie?: string) =>
      fetch(`${server.url}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
        body: JSON.stringify(body),
      });
    const registered = await post('/auth/register', {
      username: 'SecurePlayer',
      password: 'old-password-123',
    });
    const firstCookie = registered.headers.get('set-cookie')!.split(';')[0];
    const secondLogin = await post('/auth/login', {
      username: 'SecurePlayer',
      password: 'old-password-123',
    });
    const secondCookie = secondLogin.headers.get('set-cookie')!.split(';')[0];
    const profile = await (
      await fetch(`${server.url}/auth/me`, { headers: { Cookie: firstCookie } })
    ).json();
    expect(profile).toMatchObject({
      authenticated: true,
      username: 'SecurePlayer',
      email: null,
      emailVerified: false,
      createdAt: expect.any(Number),
    });
    const wrong = await post(
      '/auth/password/change',
      { currentPassword: 'wrong-password', newPassword: 'new-password-456' },
      firstCookie,
    );
    expect(wrong.status).toBe(401);
    expect((await wrong.json()).error).toBe('Текущий пароль неверен.');
    const changed = await post(
      '/auth/password/change',
      { currentPassword: 'old-password-123', newPassword: 'new-password-456' },
      firstCookie,
    );
    expect(changed.status).toBe(200);
    expect((await changed.json()).message).toContain('Остальные сеансы завершены');
    const currentCookie = changed.headers.get('set-cookie')!.split(';')[0];
    expect(
      (await (await fetch(`${server.url}/auth/me`, { headers: { Cookie: currentCookie } })).json())
        .authenticated,
    ).toBe(true);
    expect(
      (await (await fetch(`${server.url}/auth/me`, { headers: { Cookie: secondCookie } })).json())
        .authenticated,
    ).toBe(false);
    expect(
      (
        await post('/auth/login', {
          username: 'SecurePlayer',
          password: 'old-password-123',
        })
      ).status,
    ).toBe(401);
    expect(
      (
        await post('/auth/login', {
          username: 'SecurePlayer',
          password: 'new-password-456',
        })
      ).status,
    ).toBe(200);
    const database = await (await import('node:fs/promises')).readFile(authFile, 'utf8');
    expect(database).not.toContain('old-password-123');
    expect(database).not.toContain('new-password-456');
  });

  it('confirms email and resets a forgotten password with one-time mail tokens', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-email-auth-'));
    dirs.push(dir);
    const authFile = join(dir, 'accounts.json');
    const sent: Array<{ kind: 'verify' | 'reset'; message: MailMessage }> = [];
    const mailer: Mailer = {
      sendVerification: async (message) => void sent.push({ kind: 'verify', message }),
      sendPasswordReset: async (message) => void sent.push({ kind: 'reset', message }),
    };
    const server = await start({ authFile, mailer });
    const post = (path: string, body: object) =>
      fetch(`${server.url}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

    const registered = await post('/auth/register', {
      username: 'MailPlayer',
      email: 'Player@Example.com',
      password: 'old-password-123',
    });
    expect(registered.status).toBe(202);
    const registeredBody = await registered.json();
    expect(registeredBody.verificationRequired).toBe(true);
    expect(registeredBody.message).toContain('папку «Спам»');
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ kind: 'verify', message: { email: 'player@example.com' } });
    expect(
      (
        await post('/auth/register', {
          username: 'OtherMailPlayer',
          email: 'PLAYER@example.com',
          password: 'other-password-123',
        })
      ).status,
    ).toBe(409);
    expect(
      (
        await post('/auth/login', {
          username: 'MailPlayer',
          password: 'old-password-123',
        })
      ).status,
    ).toBe(403);

    const verified = await fetch(`${server.url}/auth/verify?token=${sent[0].message.token}`, {
      redirect: 'manual',
    });
    expect(verified.status).toBe(303);
    expect(verified.headers.get('location')).toBe('/?emailVerified=1');
    expect(verified.headers.get('set-cookie')).toContain('four_session=');
    expect(
      (
        await fetch(`${server.url}/auth/verify?token=${sent[0].message.token}`, {
          redirect: 'manual',
        })
      ).headers.get('location'),
    ).toBe('/?emailVerified=0');

    const requested = await post('/auth/password-reset/request', { email: 'PLAYER@example.com' });
    expect(requested.status).toBe(200);
    expect(sent.at(-1)?.kind).toBe('reset');
    const resetToken = sent.at(-1)!.message.token;
    const completed = await post('/auth/password-reset/complete', {
      token: resetToken,
      password: 'new-password-456',
    });
    expect(completed.status).toBe(200);
    expect(completed.headers.get('set-cookie')).toContain('four_session=');
    expect(
      (
        await post('/auth/login', {
          username: 'MailPlayer',
          password: 'old-password-123',
        })
      ).status,
    ).toBe(401);
    expect(
      (
        await post('/auth/login', {
          username: 'MailPlayer',
          password: 'new-password-456',
        })
      ).status,
    ).toBe(200);
    expect(
      (
        await post('/auth/password-reset/complete', {
          token: resetToken,
          password: 'another-password-789',
        })
      ).status,
    ).toBe(400);
    const database = await (await import('node:fs/promises')).readFile(authFile, 'utf8');
    expect(database).not.toContain(sent[0].message.token);
    expect(database).not.toContain(resetToken);
    expect(database).not.toContain('old-password-123');
    expect(database).not.toContain('new-password-456');
  });

  it('starts a quick game only after both players confirm the same match', async () => {
    const { connect } = await start();
    const first = await connect();
    const second = await connect();
    first.send({ type: 'quick_find', name: 'Alice' });
    await first.event('queue');
    second.send({ type: 'quick_find', name: 'Bob' });
    await second.event('queue');
    const offerA = await first.event('match_found');
    const offerB = await second.event('match_found');
    expect(offerA.matchId).toBe(offerB.matchId);
    expect(offerA.opponent).toMatch(/^Гость_\d{6}$/);
    expect(offerA.deadline - Date.now()).toBeGreaterThan(13_000);
    first.send({ type: 'quick_accept', matchId: offerA.matchId });
    first.send({ type: 'move', x: 0, y: 0, revision: 0, round: 1 });
    await first.error('ALREADY_MATCHING');
    second.send({ type: 'quick_accept', matchId: '0'.repeat(32) });
    await second.error('MATCH_NOT_FOUND');
    second.send({ type: 'quick_accept', matchId: offerB.matchId });
    const sessionA = await first.event('session');
    const sessionB = await second.event('session');
    expect(sessionA.code).toBe(sessionB.code);
    expect(sessionA.player).not.toBe(sessionB.player);
    expect(sessionA.snapshot.players[1]).not.toBeNull();
    const mover = sessionA.player === 1 ? first : second;
    move(mover, sessionA.snapshot);
    expect((await state(first, 1)).game.history).toHaveLength(1);
    expect((await state(second, 1)).game.history).toHaveLength(1);
  });

  it('returns the other player to matchmaking after a decline', async () => {
    const { connect } = await start();
    const first = await connect();
    const second = await connect();
    first.send({ type: 'quick_find', name: 'A' });
    second.send({ type: 'quick_find', name: 'B' });
    await first.event('queue');
    await second.event('queue');
    const offer = await first.event('match_found');
    await second.event('match_found');
    second.send({ type: 'quick_decline', matchId: offer.matchId });
    await second.event('queue_removed');
    await first.event('queue', (event) => event.status === 'searching');
    const third = await connect();
    third.send({ type: 'quick_find', name: 'C' });
    const next = await first.event('match_found');
    expect(next.opponent).toMatch(/^Гость_\d{6}$/);
    expect(next.matchId).not.toBe(offer.matchId);
  });

  it('removes a cancelled search so the next player is not matched to a ghost', async () => {
    const { connect } = await start();
    const first = await connect();
    first.send({ type: 'quick_find', name: 'A' });
    await first.event('queue');
    first.send({ type: 'quick_cancel' });
    await first.event('queue_removed');
    const second = await connect();
    second.send({ type: 'quick_find', name: 'B' });
    await second.event('queue');
    expect(second.events.some((event) => event.type === 'match_found')).toBe(false);
    const third = await connect();
    third.send({ type: 'quick_find', name: 'C' });
    expect((await second.event('match_found')).opponent).toMatch(/^Гость_\d{6}$/);
  });

  it('expires an unconfirmed match and keeps the confirmed player in the queue', async () => {
    const { connect } = await start({ matchConfirmMs: 80 });
    const first = await connect();
    const second = await connect();
    first.send({ type: 'quick_find', name: 'A' });
    second.send({ type: 'quick_find', name: 'B' });
    await first.event('queue');
    await second.event('queue');
    const offer = await first.event('match_found');
    await second.event('match_found');
    first.send({ type: 'quick_accept', matchId: offer.matchId });
    await first.event('queue');
    expect((await second.event('queue_removed')).message).toMatch(/истекло/);
    second.send({ type: 'quick_accept', matchId: offer.matchId });
    await second.error('MATCH_NOT_FOUND');
    const third = await connect();
    third.send({ type: 'quick_find', name: 'C' });
    expect((await first.event('match_found')).opponent).toMatch(/^Гость_\d{6}$/);
  });

  it('creates five-letter codes, joins lowercase, keeps tokens private and shares the same authoritative board', async () => {
    const { host, guest, hostSession, guestSession } = await pair();
    expect(hostSession.code).toMatch(/^[A-Z]{5}$/);
    expect(hostSession.player).toBe(1);
    expect(guestSession.player).toBe(2);
    expect(hostSession.token).not.toBe(guestSession.token);
    expect(JSON.stringify(guestSession)).not.toContain(hostSession.token);
    expect(guestSession.snapshot.players[0]?.name).toMatch(/^Гость_\d{6}$/);
    expect(guestSession.snapshot.players[1]?.name).toMatch(/^Гость_\d{6}$/);
    expect(guestSession.snapshot.players[0]?.connected).toBe(true);
    expect(guestSession.snapshot.players[1]?.connected).toBe(true);
    expect(guestSession.snapshot.startedAt).toBeTypeOf('number');
    move(host, guestSession.snapshot);
    const first = await state(host, 1);
    expect(await state(guest, 1)).toEqual(first);
    move(guest, first);
    const second = await state(guest, 2);
    expect(await state(host, 2)).toEqual(second);
    expect(second.game.history.map(({ z, player }) => [z, player])).toEqual([
      [0, 1],
      [1, 2],
    ]);
  });

  it('rejects absent/full rooms, duplicate membership, wrong turns and stale/double moves', async () => {
    const { host, guest, guestSession, connect } = await pair();
    const third = await connect();
    third.send({ type: 'join', code: guestSession.code, name: 'Third' });
    await third.error('LOBBY_FULL');
    third.send({ type: 'join', code: 'ZZZZZ', name: 'Third' });
    // The random room could be ZZZZZ; choose another code if necessary.
    await third.error(guestSession.code === 'ZZZZZ' ? 'LOBBY_FULL' : 'LOBBY_NOT_FOUND');
    host.send({ type: 'create', name: 'Again' });
    await host.error('ALREADY_IN_LOBBY');
    move(guest, guestSession.snapshot);
    await guest.error('NOT_YOUR_TURN');
    move(host, guestSession.snapshot);
    move(host, guestSession.snapshot);
    await host.error('STALE_STATE');
    const current = await state(guest, 1);
    guest.send({ type: 'move', x: 0, y: 0, revision: current.revision, round: current.round - 1 });
    await guest.error('STALE_STATE');
    move(guest, current);
    expect((await state(host, 2)).game.history).toHaveLength(2);
  });

  it('validates malformed JSON, binary messages, names, coordinates and codes without crashing', async () => {
    const { connect, url } = await start();
    const client = await connect();
    for (const payload of [
      '{bad',
      'null',
      '[]',
      '{"type":"join","code":"AB12Z","name":"X"}',
      '{"type":"create","name":12}',
      '{"type":"move","x":1.5,"y":0,"round":1,"revision":0}',
      '{"type":"move","x":5,"y":0,"round":1,"revision":0}',
      '{"type":"explode"}',
    ]) {
      client.ws.send(payload);
      await client.error('INVALID_MESSAGE');
    }
    client.ws.send(Buffer.from('{}'));
    await client.error('INVALID_MESSAGE');
    client.send({ type: 'move', x: 0, y: 0, round: 1, revision: 0 });
    await client.error('NOT_IN_LOBBY');
    client.send({ type: 'create', name: ' \n ' });
    expect((await client.event('session')).snapshot.players[0].name).toMatch(/^Гость_\d{6}$/);
    expect(await (await fetch(`${url}/health`)).json()).toEqual({ ok: true });
  });

  it('waits for both seats, preserves the game through disconnect/resume and prevents the old socket from moving', async () => {
    const server = await start();
    const host = await server.connect();
    host.send({ type: 'create', name: 'Alice' });
    const session = await host.event('session');
    move(host, session.snapshot);
    await host.error('WAITING_FOR_PLAYER');
    const guest = await server.connect();
    guest.send({ type: 'join', code: session.code, name: 'Bob' });
    const joined = await guest.event('session');
    move(host, joined.snapshot);
    await state(guest, 1);
    host.ws.terminate();
    const offline = (await guest.event('state', (event) => !event.snapshot.players[0].connected))
      .snapshot;
    move(guest, offline);
    await guest.error('WAITING_FOR_PLAYER');
    const invalid = await server.connect();
    invalid.send({ type: 'resume', code: session.code, token: '0'.repeat(64) });
    await invalid.error('INVALID_SESSION');
    const resumed = await server.connect();
    resumed.send({ type: 'resume', code: session.code, token: session.token });
    const restored = await resumed.event('session');
    expect(restored.snapshot.game.history).toHaveLength(1);
    expect(restored.player).toBe(1);
    expect(restored.token).toBe(session.token);
    const replacement = await server.connect();
    replacement.send({ type: 'resume', code: session.code, token: session.token });
    const active = await replacement.event('session');
    await resumed.event('closed');
    expect(active.snapshot.players[0].connected).toBe(true);
    move(guest, active.snapshot);
    expect((await state(replacement, 2)).game.currentPlayer).toBe(1);
  });

  it('requires mutual rematch after a verified win and rejects delayed commands from the previous round', async () => {
    const { host, guest, guestSession } = await pair();
    let current = guestSession.snapshot;
    host.send({ type: 'rematch', round: current.round });
    await host.error('GAME_NOT_FINISHED');
    for (let index = 0; index < 7; index++) {
      move(index % 2 === 0 ? host : guest, current, Math.floor(index / 2), index % 2);
      current = await state(host, index + 1);
      await state(guest, index + 1);
    }
    expect(current.game.status).toBe('won');
    expect(current.game.winner).toBe(1);
    expect(current.finishedAt).toBeTypeOf('number');
    move(host, current);
    await host.error('INVALID_MOVE');
    host.send({ type: 'rematch', round: current.round });
    const vote = (await guest.event('state', (event) => event.snapshot.rematch.length === 1))
      .snapshot;
    expect(vote.game.status).toBe('won');
    expect(vote.rematch).toEqual([1]);
    guest.send({ type: 'rematch', round: current.round });
    const next = (await host.event('state', (event) => event.snapshot.round === current.round + 1))
      .snapshot;
    expect(next.game.history).toEqual([]);
    expect(next.game.status).toBe('playing');
    expect(next.finishedAt).toBeNull();
    expect(next.rematch).toEqual([]);
    expect(next.game.currentPlayer).toBe(2);
    host.send({ type: 'move', x: 0, y: 0, round: current.round, revision: next.revision });
    await host.error('STALE_STATE');
    move(host, next);
    await host.error('NOT_YOUR_TURN');
    current = next;
    // Round two starts with the guest; round three must return to the host.
    for (let index = 0; index < 7; index++) {
      move(index % 2 === 0 ? guest : host, current, Math.floor(index / 2), index % 2);
      current = (
        await host.event(
          'state',
          (event) => event.snapshot.round === 2 && event.snapshot.game.history.length === index + 1,
        )
      ).snapshot;
    }
    expect(current.game.winner).toBe(2);
    host.send({ type: 'rematch', round: 2 });
    guest.send({ type: 'rematch', round: 2 });
    const third = (await guest.event('state', (event) => event.snapshot.round === 3)).snapshot;
    expect(third.game.currentPlayer).toBe(1);
  });

  it('rejects a full stack while keeping both players synchronized', async () => {
    const { host, guest, guestSession } = await pair();
    let current = guestSession.snapshot;
    for (let count = 1; count <= 5; count++) {
      move(count % 2 ? host : guest, current);
      current = await state(host, count);
      await state(guest, count);
    }
    move(guest, current);
    await guest.error('INVALID_MOVE');
    move(guest, current, 1, 0);
    expect((await state(host, 6)).game.heights[0]).toBe(5);
  });

  it('explicit leave closes both seats and prevents resume, while allowing a new room', async () => {
    const { host, guest, hostSession } = await pair();
    host.send({ type: 'leave' });
    await host.event('closed');
    await guest.event('closed');
    host.send({ type: 'resume', code: hostSession.code, token: hostSession.token });
    await host.error('LOBBY_NOT_FOUND');
    guest.send({ type: 'create', name: 'Bob' });
    expect((await guest.event('session')).player).toBe(1);
  });

  it('expires disconnected rooms and idle waiting rooms', async () => {
    const { host, guest, hostSession, connect } = await pair({
      disconnectGraceMs: 40,
      cleanupIntervalMs: 10,
    });
    host.ws.terminate();
    await guest.event('closed');
    const retry = await connect();
    retry.send({ type: 'resume', code: hostSession.code, token: hostSession.token });
    await retry.error('LOBBY_NOT_FOUND');
    const idleServer = await start({ idleTimeoutMs: 40, cleanupIntervalMs: 10 });
    const idle = await idleServer.connect();
    idle.send({ type: 'create', name: 'Idle' });
    await idle.event('session');
    await idle.event('closed');
  });

  it('limits rooms, incoming message rate and oversized WebSocket payloads', async () => {
    const { connect } = await start({ maxRooms: 1, messagesPerMinute: 3 });
    const first = await connect();
    first.send({ type: 'create', name: 'First' });
    await first.event('session');
    const second = await connect();
    second.send({ type: 'create', name: 'Second' });
    await second.error('SERVER_FULL');
    second.ws.send('bad');
    await second.error('INVALID_MESSAGE');
    second.ws.send('bad');
    await second.error('INVALID_MESSAGE');
    second.ws.send('bad');
    await second.error('RATE_LIMIT');
    const oversized = await connect();
    const closed = new Promise<number>((resolve) => oversized.ws.once('close', resolve));
    oversized.ws.send('a'.repeat(3000));
    expect(await closed).toBe(1009);
  });

  it('serves the production frontend, health and safe asset paths', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'four-online-'));
    dirs.push(dir);
    await writeFile(join(dir, 'index.html'), '<html>FOUR</html>');
    await writeFile(join(dir, 'app.js'), 'export {}');
    const { url } = await start({ staticDir: dir });
    expect(await (await fetch(`${url}/`)).text()).toBe('<html>FOUR</html>');
    expect(await (await fetch(`${url}/room/ABCDE`)).text()).toBe('<html>FOUR</html>');
    expect((await fetch(`${url}/app.js`)).headers.get('content-type')).toContain('javascript');
    expect((await fetch(`${url}/missing.js`)).status).toBe(404);
    expect((await fetch(`${url}/%2e%2e%5csecret.txt`)).status).toBe(403);
    expect((await fetch(`${url}/health`, { method: 'POST' })).status).toBe(405);
  });
});
