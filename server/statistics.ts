import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { deserialize, serialize, type GameState, type Player } from '../src/game/core/index.ts';
import type {
  HistoryResponse,
  MatchMode,
  SavedMatch,
  Statistics,
} from '../src/network/statistics.ts';
import { AuthError } from './auth.ts';
import { ratingDelta } from './rating.ts';
import { getLevel } from '../src/game/levels/index.ts';
import { AnalyticsStore } from './analytics.ts';

type Result = { owner: string; player: Player };
export class StatisticsStore {
  private db: DatabaseSync;
  readonly analytics: AnalyticsStore;
  constructor(
    file: string | null = process.env.FOUR_STATS_FILE ??
      resolve(dirname(process.env.FOUR_AUTH_FILE ?? 'data/accounts.json'), 'statistics.sqlite'),
  ) {
    if (file) mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(file ?? ':memory:');
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA busy_timeout = 5000;
      CREATE TABLE IF NOT EXISTS matches (
        owner TEXT NOT NULL, id TEXT NOT NULL, title TEXT NOT NULL, date INTEGER NOT NULL,
        names TEXT NOT NULL, mode TEXT NOT NULL, elapsed INTEGER NOT NULL, game TEXT NOT NULL,
        result TEXT NOT NULL CHECK(result IN ('win','loss','draw')), hidden INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner, id)
      );
      CREATE INDEX IF NOT EXISTS matches_by_owner_date ON matches(owner, date DESC);
      CREATE TABLE IF NOT EXISTS ratings (owner TEXT PRIMARY KEY, points INTEGER NOT NULL, games INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS level_progress (
        owner TEXT NOT NULL, level INTEGER NOT NULL, moves INTEGER NOT NULL,
        PRIMARY KEY(owner, level)
      );
      CREATE TABLE IF NOT EXISTS rated_rounds (id TEXT PRIMARY KEY, a TEXT NOT NULL, b TEXT NOT NULL,
        delta INTEGER NOT NULL, created INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS rated_pair ON rated_rounds(a,b,created);
    `);
    if (
      !this.db
        .prepare('PRAGMA table_info(matches)')
        .all()
        .some((c) => c.name === 'metadata')
    )
      this.db.exec("ALTER TABLE matches ADD COLUMN metadata TEXT NOT NULL DEFAULT '{}'");
    this.analytics = new AnalyticsStore(this.db);
  }

  levelProgress(owner: string) {
    const best: Record<number, number> = {};
    for (const row of this.db
      .prepare('SELECT level,moves FROM level_progress WHERE owner=?')
      .all(owner)) {
      if (getLevel(Number(row.level))) best[Number(row.level)] = Number(row.moves);
    }
    return { username: owner, best };
  }

  mergeLevelProgress(owner: string, best: unknown) {
    if (!best || typeof best !== 'object' || Array.isArray(best))
      throw new AuthError(400, 'Некорректный прогресс уровней.');
    const entries = Object.entries(best);
    if (
      entries.length > 40 ||
      entries.some(
        ([id, moves]) =>
          !/^\d+$/.test(id) ||
          !getLevel(Number(id)) ||
          typeof moves !== 'number' ||
          !Number.isInteger(moves) ||
          moves < 1 ||
          moves > 63,
      )
    )
      throw new AuthError(400, 'Некорректный результат уровня.');
    const save = this.db.prepare(`INSERT INTO level_progress(owner,level,moves) VALUES(?,?,?)
      ON CONFLICT(owner,level) DO UPDATE SET moves=MIN(level_progress.moves,excluded.moves)`);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      for (const [id, moves] of entries) save.run(owner, Number(id), moves as number);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return this.levelProgress(owner);
  }

  rating(owner: string) {
    return (
      (this.db.prepare('SELECT points,games FROM ratings WHERE owner=?').get(owner) as
        { points: number; games: number } | undefined) ?? { points: 1000, games: 0 }
    );
  }
  leaderboard(usernames: string[]) {
    const ratings = new Map(
      (
        this.db.prepare('SELECT owner,points,games FROM ratings').all() as unknown as {
          owner: string;
          points: number;
          games: number;
        }[]
      ).map((row) => [row.owner, row]),
    );
    return usernames
      .map((username) => {
        const rating = ratings.get(username);
        return { username, elo: rating?.points ?? 1000, games: rating?.games ?? 0 };
      })
      .sort(
        (a, b) =>
          b.elo - a.elo ||
          b.games - a.games ||
          a.username.toLowerCase().localeCompare(b.username.toLowerCase(), 'en'),
      )
      .slice(0, 100)
      .map((player, index) => ({ rank: index + 1, ...player }));
  }

  adminSummary(owner: string) {
    const statistics = this.db
      .prepare(
        `SELECT COUNT(*) AS total,
        COALESCE(SUM(result='win'),0) AS wins, COALESCE(SUM(result='loss'),0) AS losses,
        COALESCE(SUM(result='draw'),0) AS draws FROM matches WHERE owner=?`,
      )
      .get(owner) as unknown as Statistics;
    return { rating: this.rating(owner), statistics };
  }
  setRating(owner: string, points: number) {
    if (!Number.isSafeInteger(points) || points < 0 || points > 1_000_000)
      throw new AuthError(400, 'Elo должен быть целым числом от 0 до 1 000 000.');
    const current = this.rating(owner);
    this.db
      .prepare(
        `INSERT INTO ratings(owner,points,games) VALUES(?,?,?)
        ON CONFLICT(owner) DO UPDATE SET points=excluded.points`,
      )
      .run(owner, points, current.games);
  }
  renameOwner(previous: string, next: string) {
    if (previous === next) return;
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db.prepare('UPDATE matches SET owner=? WHERE owner=?').run(next, previous);
      this.db.prepare('UPDATE ratings SET owner=? WHERE owner=?').run(next, previous);
      this.db.prepare('UPDATE level_progress SET owner=? WHERE owner=?').run(next, previous);
      this.db.prepare('UPDATE rated_rounds SET a=? WHERE a=?').run(next, previous);
      this.db.prepare('UPDATE rated_rounds SET b=? WHERE b=?').run(next, previous);
      this.analytics.renameOwner(previous, next);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }
  deleteOwner(owner: string) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db
        .prepare('DELETE FROM matches WHERE id IN (SELECT id FROM matches WHERE owner=?)')
        .run(owner);
      this.db.prepare('DELETE FROM ratings WHERE owner=?').run(owner);
      this.db.prepare('DELETE FROM level_progress WHERE owner=?').run(owner);
      this.db.prepare('DELETE FROM rated_rounds WHERE a=? OR b=?').run(owner, owner);
      this.analytics.deleteOwner(owner);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }
  canRank(a: string, b: string) {
    const row = this.db
      .prepare(
        'SELECT COUNT(*) AS n FROM rated_rounds WHERE ((a=? AND b=?) OR (a=? AND b=?)) AND created>?',
      )
      .get(a, b, b, a, Date.now() - 86400000)!;
    return a !== b && Number(row.n) < 3;
  }

  record(
    id: string,
    game: GameState,
    names: [string, string],
    mode: MatchMode,
    elapsed: number,
    date: number,
    results: Result[],
    ranked = false,
    endReason?: string,
  ) {
    if (game.status === 'playing') return;
    const insert = this.db
      .prepare(`INSERT INTO matches(owner,id,title,date,names,mode,elapsed,game,result,metadata)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(owner,id) DO NOTHING`);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      let delta: number | undefined;
      if (ranked && results.length === 2 && results[0].owner !== results[1].owner) {
        const [a, b] = results;
        const existing = this.db.prepare('SELECT delta FROM rated_rounds WHERE id=?').get(id);
        if (existing) delta = Number(existing.delta);
        else {
          const ra = this.rating(a.owner),
            rb = this.rating(b.owner);
          delta = ratingDelta(
            ra.points,
            rb.points,
            game.winner === null ? 0.5 : game.winner === a.player ? 1 : 0,
          );
          this.db
            .prepare('INSERT INTO rated_rounds VALUES(?,?,?,?,?)')
            .run(id, a.owner, b.owner, delta, date);
          const update = this.db.prepare(
            'INSERT INTO ratings VALUES(?,?,?) ON CONFLICT(owner) DO UPDATE SET points=excluded.points,games=excluded.games',
          );
          update.run(a.owner, ra.points + delta, ra.games + 1);
          update.run(b.owner, rb.points - delta, rb.games + 1);
        }
      }
      // A person occupying both seats still gets at most one result for this round.
      this.analytics.recordCompleted(id, game, names, mode, elapsed, date, results, ranked);
      for (const { owner, player } of results) {
        insert.run(
          owner,
          id,
          `${names[0]} — ${names[1]}`,
          date,
          JSON.stringify(names),
          mode,
          elapsed,
          serialize(game),
          game.winner === null ? 'draw' : game.winner === player ? 'win' : 'loss',
          JSON.stringify({
            winner: game.winner,
            endReason,
            ...(delta === undefined
              ? {}
              : {
                  ratingChange: owner === results[0].owner ? delta : -delta,
                  ratingAfter: this.rating(owner).points,
                }),
          }),
        );
      }
      this.db.exec('COMMIT');
      return delta === undefined ? undefined : ([delta, -delta] as [number, number]);
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  saveLocal(owner: string, data: Record<string, unknown>) {
    if (data.owner !== owner) throw new AuthError(403, 'Аккаунт изменился. Начните новую партию.');
    if (
      typeof data.id !== 'string' ||
      !/^local-[a-zA-Z0-9-]{1,100}$/.test(data.id) ||
      !['local', 'ai'].includes(String(data.mode)) ||
      typeof data.game !== 'string' ||
      data.game.length > 10000 ||
      typeof data.elapsed !== 'number' ||
      !Number.isSafeInteger(data.elapsed) ||
      data.elapsed < 0 ||
      data.elapsed > 604800 ||
      !Array.isArray(data.names) ||
      data.names.length !== 2 ||
      !data.names.every((name) => typeof name === 'string' && name.length <= 24)
    )
      throw new AuthError(400, 'Некорректная партия.');
    let game: GameState;
    try {
      game = deserialize(data.game);
    } catch {
      throw new AuthError(400, 'Некорректные ходы партии.');
    }
    if (game.status === 'playing') throw new AuthError(400, 'Партия ещё не завершена.');
    const names: [string, string] = [owner, data.mode === 'ai' ? 'FOUR AI' : data.names[1]];
    this.record(data.id, game, names, data.mode as 'local' | 'ai', data.elapsed, Date.now(), [
      { owner, player: 1 },
    ]);
  }

  read(owner: string): HistoryResponse {
    const rows = this.db
      .prepare(
        `SELECT id,title,date,names,mode,elapsed,game,metadata FROM matches
      WHERE owner=? AND hidden=0 ORDER BY date DESC, rowid DESC LIMIT 50`,
      )
      .all(owner);
    const statistics = this.db
      .prepare(
        `SELECT COUNT(*) AS total,
      COALESCE(SUM(result='win'),0) AS wins, COALESCE(SUM(result='loss'),0) AS losses,
      COALESCE(SUM(result='draw'),0) AS draws FROM matches WHERE owner=?`,
      )
      .get(owner) as unknown as Statistics;
    return {
      username: owner,
      statistics,
      rating: this.rating(owner),
      matches: rows.map(({ metadata, ...row }) => ({
        ...row,
        names: JSON.parse(row.names as string),
        ...JSON.parse(metadata as string),
      })) as unknown as SavedMatch[],
    };
  }

  rename(owner: string, id: string, title: string) {
    const clean = title.trim();
    if (!clean || clean.length > 80)
      throw new AuthError(400, 'Название должно содержать от 1 до 80 символов.');
    if (
      !this.db
        .prepare('UPDATE matches SET title=? WHERE owner=? AND id=? AND hidden=0')
        .run(clean, owner, id).changes
    )
      throw new AuthError(404, 'Партия не найдена.');
  }
  remove(owner: string, id: string) {
    if (
      !this.db
        .prepare('UPDATE matches SET hidden=1 WHERE owner=? AND id=? AND hidden=0')
        .run(owner, id).changes
    )
      throw new AuthError(404, 'Партия не найдена.');
  }
  close() {
    this.db.close();
  }
}
