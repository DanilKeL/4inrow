import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DatabaseSync } from 'node:sqlite';
import { StatisticsStore } from './statistics';
import { createGame, makeMove, serialize } from '../src/game/core';
import type { AnalyticsFilter } from '../src/network/analyticsTypes';

const filter: AnalyticsFilter = {
  from: '2026-10-01',
  to: '2026-10-07',
  mode: 'all',
  device: 'all',
};
const visit = {
  type: 'visit',
  session: 'session-00001',
  visitor: 'visitor-00001',
  device: 'mobile',
  browser: 'Safari',
  referrer: 'https://yandex.ru/search?private=discarded',
};
const start = {
  type: 'game_start',
  session: visit.session,
  visitor: visit.visitor,
  id: 'local-match-0001',
  mode: 'ai',
  difficulty: 'hard',
};
function win() {
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
  return game;
}
let store: StatisticsStore;
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime('2026-10-02T12:00:00Z');
  store = new StatisticsStore(null);
});
afterEach(() => {
  store.close();
  vi.useRealTimers();
});

describe('analytics data integrity', () => {
  it('upgrades fallback account history when delayed telemetry arrives, without counting it twice', () => {
    store.record(start.id, win(), ['Alice', 'FOUR AI'], 'ai', 40, Date.now(), [
      { owner: 'Alice', player: 1 },
    ]);
    expect(store.analytics.dashboard(filter, []).bots[0].difficulty).toBe('unknown');
    store.analytics.ingest(visit, 'Alice');
    store.analytics.ingest(start, 'Alice');
    const data = store.analytics.dashboard(filter, []);
    expect(data.summary).toMatchObject({ started: 1, completed: 1 });
    expect(data.bots[0]).toMatchObject({ difficulty: 'hard', wins: 1 });
  });
  it('deduplicates visits, game starts and outcomes and records human results by difficulty', () => {
    store.analytics.ingest(visit, 'Alice');
    store.analytics.ingest(visit, 'Alice');
    store.analytics.ingest(start, 'Alice');
    store.analytics.ingest(start, 'Alice');
    const end = {
      type: 'game_end',
      id: start.id,
      session: visit.session,
      visitor: visit.visitor,
      game: serialize(win()),
      elapsed: 120,
    };
    store.analytics.ingest(end, 'Alice');
    store.analytics.ingest(end, 'Alice');
    const data = store.analytics.dashboard(filter, []);
    expect(data.summary).toMatchObject({
      visitors: 1,
      sessions: 1,
      started: 1,
      completed: 1,
      registeredPlayers: 1,
      guestPlayers: 0,
      averageGameSeconds: 120,
    });
    expect(data.bots).toEqual([
      expect.objectContaining({
        difficulty: 'hard',
        wins: 1,
        losses: 0,
        completed: 1,
        averageMoves: 4,
      }),
    ]);
    expect(data.players[0]).toMatchObject({ username: 'Alice', ai: 1, wins: 1, games: 1 });
    expect(data.sources[0].name).toBe('yandex.ru');
  });
  it('records online rounds once and gives both participants the correct outcome, including rematches', () => {
    store.analytics.onlineStart('online-round-01', 'ranked', ['Alice', 'Bob'], Date.now());
    store.analytics.onlineStart('online-round-01', 'ranked', ['Alice', 'Bob'], Date.now());
    store.analytics.onlineEnd('online-round-01', win(), 42, Date.now());
    store.analytics.onlineEnd('online-round-01', win(), 42, Date.now());
    store.analytics.onlineStart('online-round-02', 'ranked', ['Alice', 'Bob'], Date.now());
    store.analytics.onlineAbandon('online-round-02');
    const data = store.analytics.dashboard(filter, []);
    expect(data.summary).toMatchObject({
      started: 2,
      completed: 1,
      abandoned: 1,
      registeredPlayers: 2,
    });
    expect(data.players.find((p) => p.username === 'Alice')).toMatchObject({
      wins: 1,
      losses: 0,
      games: 2,
    });
    expect(data.players.find((p) => p.username === 'Bob')).toMatchObject({
      wins: 0,
      losses: 1,
      games: 2,
    });
  });
  it('distinguishes guest participation, abandoned attempts, modes and devices', () => {
    store.analytics.ingest(visit, null, 'Гость_123456');
    store.analytics.ingest({ ...start, mode: 'level', level: 3 }, null, 'Гость_123456');
    store.analytics.ingest(
      {
        type: 'game_abandon',
        session: visit.session,
        visitor: visit.visitor,
        id: start.id,
        elapsed: 5,
      },
      null,
    );
    store.analytics.onlineStart('guest-online-01', 'lobby', [null, null], Date.now(), [
      'Гость_123456',
      'Гость_654321',
    ]);
    const data = store.analytics.dashboard(filter, []);
    expect(data.summary.guestPlayers).toBe(2);
    expect(data.levels[0]).toMatchObject({
      level: 3,
      started: 1,
      completed: 0,
      wins: 0,
      bestMoves: null,
    });
    expect(store.analytics.dashboard({ ...filter, mode: 'ai' }, []).summary.started).toBe(0);
    expect(store.analytics.dashboard({ ...filter, device: 'mobile' }, []).summary.started).toBe(2);
    expect(store.analytics.dashboard({ ...filter, device: 'desktop' }, []).summary.sessions).toBe(
      0,
    );
  });
  it('tracks active time idempotently and returning visitors across days', () => {
    store.analytics.ingest(visit, null);
    vi.setSystemTime('2026-10-02T12:00:30Z');
    const heartbeat = {
      type: 'heartbeat',
      session: visit.session,
      visitor: visit.visitor,
      activeSeconds: 30,
    };
    store.analytics.ingest(heartbeat, null);
    store.analytics.ingest(heartbeat, null);
    expect(store.analytics.dashboard(filter, []).summary.averageActiveSeconds).toBe(30);
    vi.setSystemTime('2026-10-03T12:00:00Z');
    store.analytics.ingest({ ...visit, session: 'session-00002' }, null);
    const data = store.analytics.dashboard({ ...filter, from: '2026-10-03', to: '2026-10-03' }, []);
    expect(data.summary).toMatchObject({
      sessions: 1,
      visitors: 1,
      returningVisitors: 1,
      activeNow: 1,
      previousVisitors: 1,
    });
  });
  it('rejects spoofing, uncompleted outcomes, invalid dimensions and excessive date ranges', () => {
    store.analytics.ingest(visit, 'Alice');
    store.analytics.ingest(start, 'Alice');
    expect(() =>
      store.analytics.ingest({ ...visit, visitor: 'different-visitor' }, 'Alice'),
    ).toThrow('Сеанс не совпадает');
    expect(() =>
      store.analytics.ingest({ ...start, id: 'ranked-client-01', mode: 'ranked' }, 'Alice'),
    ).toThrow('Некорректный режим');
    expect(() =>
      store.analytics.ingest(
        { ...start, type: 'game_end', elapsed: 10, game: serialize(createGame()) },
        'Alice',
      ),
    ).toThrow('не завершена');
    expect(() =>
      store.analytics.dashboard(
        { ...filter, mode: "ai' OR 1=1 --" as AnalyticsFilter['mode'] },
        [],
      ),
    ).toThrow('корректный период');
    expect(() => store.analytics.dashboard({ ...filter, from: '2020-01-01' }, [])).toThrow(
      'корректный период',
    );
    expect(() => store.analytics.dashboard({ ...filter, from: '2026-02-30' }, [])).toThrow(
      'корректный период',
    );
    store.analytics.onlineStart('server-match-01', 'ranked', ['Alice', 'Bob'], Date.now());
    expect(() => store.analytics.ingest({ ...start, id: 'server-match-01' }, 'Alice')).toThrow(
      'Партия не совпадает',
    );
  });
  it('renames accounts consistently and anonymizes analytics on deletion without losing totals', () => {
    store.analytics.ingest(visit, 'Alice');
    store.analytics.ingest(start, 'Alice');
    store.renameOwner('Alice', 'Renamed');
    expect(store.analytics.dashboard(filter, []).players[0].username).toBe('Renamed');
    store.deleteOwner('Renamed');
    const data = store.analytics.dashboard(filter, []);
    expect(data.players).toHaveLength(0);
    expect(data.summary.started).toBe(1);
  });
  it('backfills a legacy online match only once and retains unknown bot difficulty', () => {
    const db = new DatabaseSync(':memory:');
    db.exec(`CREATE TABLE matches(owner TEXT,id TEXT,mode TEXT,date INTEGER,elapsed INTEGER,result TEXT);
      CREATE TABLE rated_rounds(id TEXT);
      INSERT INTO matches VALUES('Alice','old-online','online',1790942400000,60,'win'),('Bob','old-online','online',1790942400000,60,'loss'),('Alice','old-bot','ai',1790942400000,60,'loss');
      INSERT INTO rated_rounds VALUES('old-online');`);
    // The migration uses only the public store class and real SQLite schema.
    const Analytics = store.analytics.constructor as new (
      db: DatabaseSync,
    ) => typeof store.analytics;
    const migrated = new Analytics(db);
    const first = migrated.dashboard(filter, []);
    expect(first.summary.completed).toBe(2);
    expect(first.bots[0]).toMatchObject({ difficulty: 'unknown', losses: 1 });
    expect(first.players.find((p) => p.username === 'Bob')?.losses).toBe(1);
    expect(new Analytics(db).dashboard(filter, []).summary.completed).toBe(2);
    db.close();
  });
});
