import { afterEach, expect, it } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { replay, serialize, createGame } from '../src/game/core/index';
import { StatisticsStore } from './statistics';
import { DatabaseSync } from 'node:sqlite';
const stores: StatisticsStore[] = [];
const dirs: string[] = [];
it('persists level bests, merges devices atomically, renames and deletes account progress', () => {
  const dir = mkdtempSync(join(tmpdir(), 'four-levels-'));
  dirs.push(dir);
  const file = join(dir, 'stats.sqlite');
  const db = open(file);
  db.mergeLevelProgress('Alice', { 1: 5, 2: 7 });
  db.mergeLevelProgress('Alice', { 1: 8, 2: 3, 3: 4 });
  expect(db.levelProgress('Alice').best).toEqual({ 1: 5, 2: 3, 3: 4 });
  expect(db.levelProgress('Bob').best).toEqual({});
  expect(() => db.mergeLevelProgress('Alice', { 1: 1, 41: 2 })).toThrow();
  expect(db.levelProgress('Alice').best[1]).toBe(5);
  db.close();
  stores.splice(stores.indexOf(db), 1);
  const reopened = open(file);
  expect(reopened.levelProgress('Alice').best[2]).toBe(3);
  reopened.renameOwner('Alice', 'Renamed');
  expect(reopened.levelProgress('Renamed').best[1]).toBe(5);
  reopened.deleteOwner('Renamed');
  expect(reopened.levelProgress('Renamed').best).toEqual({});
});
it('returns a public top 100 with stable ties, defaults, and current account names only', () => {
  const db = open(null);
  db.setRating('Winner', 1600);
  db.setRating('Deleted', 2000);
  db.setRating('Alice', 1000);
  const names = ['Winner', 'Bob', 'Alice', ...Array.from({ length: 110 }, (_, i) => `User${i}`)];
  const players = db.leaderboard(names);
  expect(players).toHaveLength(100);
  expect(players[0]).toEqual({ rank: 1, username: 'Winner', elo: 1600, games: 0 });
  expect(players[1]).toEqual({ rank: 2, username: 'Alice', elo: 1000, games: 0 });
  expect(players[2].username).toBe('Bob');
  expect(players[99].rank).toBe(100);
  expect(players.some((player) => player.username === 'Deleted')).toBe(false);
  db.record(
    'leaderboard-round',
    game,
    ['Bob', 'Alice'],
    'online',
    10,
    Date.now(),
    [
      { owner: 'Bob', player: 1 },
      { owner: 'Alice', player: 2 },
    ],
    true,
  );
  db.setRating('Bob', 1000);
  expect(db.leaderboard(['Aaron', 'Bob'])[0]).toEqual({
    rank: 1,
    username: 'Bob',
    elo: 1000,
    games: 1,
  });
  db.renameOwner('Winner', 'Renamed');
  expect(db.leaderboard(['Renamed'])[0].elo).toBe(1600);
  db.deleteOwner('Renamed');
  expect(db.leaderboard([])).toEqual([]);
});
it('upgrades the previous database without changing existing history or awarding retroactive Elo', () => {
  const dir = mkdtempSync(join(tmpdir(), 'four-migrate-'));
  dirs.push(dir);
  const file = join(dir, 'stats.sqlite');
  const legacy = new DatabaseSync(file);
  legacy.exec(`CREATE TABLE matches (owner TEXT NOT NULL,id TEXT NOT NULL,title TEXT NOT NULL,date INTEGER NOT NULL,
    names TEXT NOT NULL,mode TEXT NOT NULL,elapsed INTEGER NOT NULL,game TEXT NOT NULL,result TEXT NOT NULL,hidden INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(owner,id));`);
  legacy
    .prepare('INSERT INTO matches VALUES(?,?,?,?,?,?,?,?,?,?)')
    .run(
      'Alice',
      'legacy',
      'Old win',
      1,
      JSON.stringify(['Alice', 'Bob']),
      'online',
      40,
      serialize(game),
      'win',
      0,
    );
  legacy.close();
  const db = open(file);
  expect(db.read('Alice').statistics.wins).toBe(1);
  expect(db.read('Alice').matches[0].title).toBe('Old win');
  expect(db.rating('Alice')).toEqual({ points: 1000, games: 0 });
});
const game = replay(
  [
    [0, 0],
    [0, 4],
    [1, 0],
    [1, 4],
    [2, 0],
    [2, 4],
    [3, 0],
  ].map(([x, y]) => ({ x, y })),
);
function open(file: string | null = null) {
  const db = new StatisticsStore(file);
  stores.push(db);
  return db;
}
afterEach(() => {
  for (const db of stores.splice(0)) db.close();
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

it('persists private results, handles both player seats, and does not count duplicates', () => {
  const dir = mkdtempSync(join(tmpdir(), 'four-stats-'));
  dirs.push(dir);
  const file = join(dir, 'stats.sqlite');
  const db = open(file);
  const save = () =>
    db.record('online-round-1', game, ['Alice', 'Bob'], 'online', 42, 100, [
      { owner: 'Alice', player: 1 },
      { owner: 'Bob', player: 2 },
    ]);
  save();
  save();
  expect(db.read('Alice').statistics).toEqual({ total: 1, wins: 1, losses: 0, draws: 0 });
  expect(db.read('Bob').statistics.losses).toBe(1);
  expect(db.read('Stranger').matches).toEqual([]);
  expect(() => db.rename('Stranger', 'online-round-1', 'stolen')).toThrow('не найдена');
  db.rename('Alice', 'online-round-1', 'Моя победа');
  expect(db.read('Bob').matches[0].title).not.toBe('Моя победа');
  db.close();
  stores.splice(stores.indexOf(db), 1);
  const restored = open(file);
  expect(restored.read('Alice').matches[0].title).toBe('Моя победа');
  restored.remove('Alice', 'online-round-1');
  expect(restored.read('Alice').matches).toEqual([]);
  expect(restored.read('Alice').statistics.total).toBe(1);
});

it('validates local results and refuses client-submitted online wins', () => {
  const db = open();
  const data = {
    id: 'local-1',
    owner: 'Alice',
    game: serialize(game),
    names: ['Fake', 'Guest'],
    mode: 'ai',
    elapsed: 15,
  };
  db.saveLocal('Alice', data);
  expect(db.read('Alice').matches[0].names).toEqual(['Alice', 'FOUR AI']);
  expect(() => db.saveLocal('Bob', data)).toThrow('Аккаунт');
  expect(() => db.saveLocal('Alice', { ...data, mode: 'online' })).toThrow('Некорректная');
  expect(() => db.saveLocal('Alice', { ...data, game: serialize(createGame()) })).toThrow(
    'не завершена',
  );
});

it('persists Elo atomically once per round, keeps it after deletion, and limits repeated pairs', () => {
  const dir = mkdtempSync(join(tmpdir(), 'four-rating-'));
  dirs.push(dir);
  const file = join(dir, 'stats.sqlite');
  const db = open(file);
  const save = (id: string) =>
    db.record(
      id,
      game,
      ['Alice', 'Bob'],
      'online',
      40,
      Date.now(),
      [
        { owner: 'Alice', player: 1 },
        { owner: 'Bob', player: 2 },
      ],
      true,
    );
  expect(db.rating('Alice')).toEqual({ points: 1000, games: 0 });
  expect(save('rank-1')).toEqual([16, -16]);
  save('rank-1');
  expect(db.rating('Alice')).toEqual({ points: 1016, games: 1 });
  expect(db.read('Bob').matches[0]).toMatchObject({ ratingChange: -16, ratingAfter: 984 });
  db.remove('Alice', 'rank-1');
  expect(db.rating('Alice').points).toBe(1016);
  save('rank-2');
  save('rank-3');
  expect(db.canRank('Alice', 'Bob')).toBe(false);
  expect(db.canRank('Bob', 'Alice')).toBe(false);
  expect(db.canRank('Alice', 'Alice')).toBe(false);
  expect(db.canRank('Alice', 'Other')).toBe(true);
  db.close();
  stores.splice(stores.indexOf(db), 1);
  const restored = open(file);
  expect(restored.rating('Alice').games).toBe(3);
  expect(restored.rating('Alice').points + restored.rating('Bob').points).toBe(2000);
});

it('keeps lifetime statistics beyond the 50 most recent replay records', () => {
  const db = open();
  for (let i = 0; i < 55; i++)
    db.record(`local-${i}`, game, ['Alice', 'Guest'], 'local', 1, i, [
      { owner: 'Alice', player: 1 },
    ]);
  expect(db.read('Alice').matches).toHaveLength(50);
  expect(db.read('Alice').statistics.total).toBe(55);
});

it('counts a complete legal draw for each participant', () => {
  const columns = [
    2, 7, 11, 14, 24, 8, 21, 1, 6, 14, 15, 9, 3, 20, 14, 16, 1, 17, 5, 23, 13, 16, 17, 18, 2, 21,
    17, 6, 7, 3, 23, 8, 8, 10, 13, 5, 12, 3, 3, 3, 14, 14, 20, 20, 5, 1, 16, 13, 22, 12, 20, 23, 18,
    1, 24, 1, 4, 22, 22, 24, 15, 24, 9, 2, 17, 13, 0, 24, 10, 12, 10, 12, 10, 17, 6, 23, 4, 15, 11,
    5, 11, 11, 22, 21, 2, 21, 20, 7, 2, 9, 11, 16, 4, 16, 12, 23, 21, 5, 13, 4, 8, 10, 7, 9, 7, 9,
    8, 18, 18, 0, 0, 15, 6, 22, 15, 0, 19, 18, 4, 6, 0, 19, 19, 19, 19,
  ];
  const draw = replay(columns.map((column) => ({ x: column % 5, y: Math.floor(column / 5) })));
  const db = open();
  db.record('online-draw', draw, ['Alice', 'Bob'], 'online', 100, Date.now(), [
    { owner: 'Alice', player: 1 },
    { owner: 'Bob', player: 2 },
  ]);
  for (const owner of ['Alice', 'Bob'])
    expect(db.read(owner).statistics).toEqual({ total: 1, wins: 0, losses: 0, draws: 1 });
});
