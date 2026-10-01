import type { DatabaseSync } from 'node:sqlite';
import { AuthError } from './auth.ts';
import { deserialize, type GameState } from '../src/game/core/index.ts';
import { getLevel, levelMoveCount } from '../src/game/levels/index.ts';
import type {
  AnalyticsDashboard,
  AnalyticsFilter,
  AnalyticsMode,
} from '../src/network/analyticsTypes.ts';

const modes: AnalyticsMode[] = ['ranked', 'ai', 'level', 'lobby', 'local'];
const token = (value: unknown): value is string =>
  typeof value === 'string' && /^[a-zA-Z0-9-]{8,140}$/.test(value);
const count = (value: unknown, max: number): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 && value <= max;
type Account = {
  username: string;
  createdAt: number | null;
  emailVerified: boolean;
  disabled: boolean;
};

export class AnalyticsStore {
  constructor(private db: DatabaseSync) {
    db.exec(`
      CREATE TABLE IF NOT EXISTS analytics_meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS analytics_sessions (
        id TEXT PRIMARY KEY, visitor TEXT NOT NULL, owner TEXT, identity TEXT, started INTEGER NOT NULL,
        last_seen INTEGER NOT NULL, active_seconds INTEGER NOT NULL DEFAULT 0,
        device TEXT NOT NULL, browser TEXT NOT NULL, source TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS analytics_sessions_started ON analytics_sessions(started);
      CREATE INDEX IF NOT EXISTS analytics_sessions_visitor ON analytics_sessions(visitor,started);
      CREATE TABLE IF NOT EXISTS analytics_games (
        id TEXT PRIMARY KEY, session TEXT, visitor TEXT, p1 TEXT, p2 TEXT, guest1 TEXT, guest2 TEXT,
        mode TEXT NOT NULL, difficulty TEXT, level INTEGER, started INTEGER NOT NULL,
        ended INTEGER, result TEXT, elapsed INTEGER NOT NULL DEFAULT 0, moves INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL, device TEXT NOT NULL DEFAULT 'unknown'
      );
      CREATE INDEX IF NOT EXISTS analytics_games_started ON analytics_games(started);
      CREATE INDEX IF NOT EXISTS analytics_games_players ON analytics_games(p1,p2);
    `);
    db.prepare("INSERT OR IGNORE INTO analytics_meta VALUES('collection_started',?)").run(
      Date.now(),
    );
    // Import once. One online round can have two account history rows.
    if (!db.prepare("SELECT value FROM analytics_meta WHERE key='history_imported'").get()) {
      db.exec(`INSERT OR IGNORE INTO analytics_games(id,p1,p2,mode,difficulty,started,ended,result,elapsed,moves,source)
        SELECT id,MIN(owner),CASE WHEN mode='online' AND COUNT(*)>1 THEN MAX(owner) ELSE NULL END,
          CASE WHEN mode='online' THEN 'lobby' ELSE mode END,
          CASE WHEN mode='ai' THEN 'unknown' ELSE NULL END,
          MAX(0,date-elapsed*1000),date,
          (SELECT result FROM matches m2 WHERE m2.id=matches.id ORDER BY owner LIMIT 1),elapsed,0,'history'
        FROM matches GROUP BY id;
        INSERT INTO analytics_meta VALUES('history_imported',1);`);
      // Recorded Elo rounds are identifiable even in the old database.
      db.exec("UPDATE analytics_games SET mode='ranked' WHERE id IN (SELECT id FROM rated_rounds)");
    }
  }

  ingest(data: Record<string, unknown>, owner: string | null, identity: string | null = owner) {
    if (!token(data.session) || !token(data.visitor))
      throw new AuthError(400, 'Некорректный сеанс.');
    const now = Date.now();
    const occurredAt =
      count(data.occurredAt, now + 60000) && data.occurredAt >= now - 7 * 86400000
        ? Math.min(now, data.occurredAt)
        : now;
    const session = this.db
      .prepare('SELECT * FROM analytics_sessions WHERE id=?')
      .get(data.session);
    if (session && session.visitor !== data.visitor)
      throw new AuthError(403, 'Сеанс не совпадает.');
    if (data.type === 'visit') {
      if (
        !['desktop', 'mobile', 'tablet'].includes(String(data.device)) ||
        !['Chrome', 'Safari', 'Firefox', 'Edge', 'Yandex', 'Samsung', 'Other'].includes(
          String(data.browser),
        )
      )
        throw new AuthError(400, 'Некорректное устройство.');
      let source = 'Прямой вход';
      if (typeof data.referrer === 'string' && data.referrer.length <= 2048 && data.referrer) {
        try {
          source = new URL(data.referrer).hostname.toLowerCase();
        } catch {
          /* Direct visit. */
        }
        if (['4inrow.ru', 'www.4inrow.ru', 'localhost', '127.0.0.1'].includes(source))
          source = 'Прямой вход';
      }
      this.db
        .prepare(
          `INSERT INTO analytics_sessions(id,visitor,owner,identity,started,last_seen,device,browser,source)
        VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET last_seen=excluded.last_seen,owner=excluded.owner,identity=excluded.identity`,
        )
        .run(
          data.session,
          data.visitor,
          owner,
          identity,
          occurredAt,
          now,
          String(data.device),
          String(data.browser),
          source,
        );
      return;
    }
    if (!session) throw new AuthError(409, 'Сначала зарегистрируйте посещение.');
    if (data.type === 'heartbeat') {
      if (!count(data.activeSeconds, 604800)) throw new AuthError(400, 'Некорректное время.');
      const elapsedLimit = Math.floor((now - Number(session.started)) / 1000) + 2;
      this.db
        .prepare(
          `UPDATE analytics_sessions SET last_seen=?,owner=?,active_seconds=MAX(active_seconds,?) WHERE id=?`,
        )
        .run(
          now,
          data.owner === undefined || data.owner === owner ? owner : null,
          Math.min(data.activeSeconds, elapsedLimit, Number(session.active_seconds) + 65),
          data.session,
        );
      return;
    }
    if (!token(data.id)) throw new AuthError(400, 'Некорректная партия.');
    const game = this.db.prepare('SELECT * FROM analytics_games WHERE id=?').get(data.id);
    const legacyOwner = game?.source === 'legacy' && owner !== null && game.p1 === owner;
    if (game && !legacyOwner && (game.session !== data.session || game.source !== 'client'))
      throw new AuthError(403, 'Партия не совпадает.');
    if (data.type === 'game_start') {
      if (
        !['ai', 'local', 'level'].includes(String(data.mode)) ||
        (data.mode === 'ai' && !['easy', 'medium', 'hard'].includes(String(data.difficulty))) ||
        (data.mode === 'level' && (!count(data.level, 40) || !getLevel(data.level)))
      )
        throw new AuthError(400, 'Некорректный режим.');
      if (legacyOwner && game?.mode === data.mode) {
        this.db
          .prepare(
            `UPDATE analytics_games SET session=?,visitor=?,difficulty=?,device=?,source='client' WHERE id=?`,
          )
          .run(
            data.session,
            data.visitor,
            data.mode === 'ai' ? String(data.difficulty) : null,
            session.device,
            data.id,
          );
        return;
      }
      this.db
        .prepare(
          `INSERT OR IGNORE INTO analytics_games(id,session,visitor,p1,guest1,mode,difficulty,level,started,source,device)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
        )
        .run(
          data.id,
          data.session,
          data.visitor,
          data.owner === undefined || data.owner === owner ? owner : null,
          !owner ? (identity ?? data.visitor) : null,
          String(data.mode),
          data.mode === 'ai' ? String(data.difficulty) : null,
          data.mode === 'level' ? Number(data.level) : null,
          occurredAt,
          'client',
          session.device,
        );
      return;
    }
    if (!game) throw new AuthError(409, 'Партия ещё не зарегистрирована.');
    if (game.ended !== null) return;
    if (!count(data.elapsed, 604800)) throw new AuthError(400, 'Некорректное время партии.');
    if (data.type === 'game_abandon') {
      this.db
        .prepare("UPDATE analytics_games SET ended=?,result='abandoned',elapsed=? WHERE id=?")
        .run(Math.max(Number(game.started), occurredAt), data.elapsed, data.id);
      return;
    }
    if (data.type !== 'game_end' || typeof data.game !== 'string' || data.game.length > 10000)
      throw new AuthError(400, 'Некорректный результат.');
    let state: GameState;
    try {
      state = deserialize(data.game);
    } catch {
      throw new AuthError(400, 'Некорректные ходы.');
    }
    if (state.status === 'playing') throw new AuthError(400, 'Партия не завершена.');
    const level = getLevel(Number(game.level));
    if (
      game.mode === 'level' &&
      (!level ||
        !level.preset.every(
          (move, i) => state.history[i]?.x === move.x && state.history[i]?.y === move.y,
        ))
    )
      throw new AuthError(400, 'Позиция уровня не совпадает.');
    this.db
      .prepare('UPDATE analytics_games SET ended=?,result=?,elapsed=?,moves=? WHERE id=?')
      .run(
        Math.max(Number(game.started), occurredAt),
        state.winner === null ? 'draw' : state.winner === 1 ? 'win' : 'loss',
        data.elapsed,
        level ? levelMoveCount(state, level) : state.history.filter((m) => m.player === 1).length,
        data.id,
      );
  }

  onlineStart(
    id: string,
    mode: 'ranked' | 'lobby',
    players: [string | null, string | null],
    started: number,
    identities: [string, string] = ['', ''],
  ) {
    const session = this.db
      .prepare(
        'SELECT * FROM analytics_sessions WHERE (owner=? OR identity=?) AND last_seen>? ORDER BY last_seen DESC LIMIT 1',
      )
      .get(players[0], identities[0] || players[0], started - 5 * 60_000);
    this.db
      .prepare(
        `INSERT OR IGNORE INTO analytics_games(id,p1,p2,guest1,guest2,mode,started,source,device) VALUES(?,?,?,?,?,?,?,'server',?)`,
      )
      .run(
        id,
        players[0],
        players[1],
        players[0] ? null : identities[0] || null,
        players[1] ? null : identities[1] || null,
        mode,
        started,
        session?.device ?? 'unknown',
      );
  }
  onlineEnd(id: string, game: GameState, elapsed: number, ended: number) {
    this.db
      .prepare(
        'UPDATE analytics_games SET ended=?,result=?,elapsed=?,moves=? WHERE id=? AND ended IS NULL',
      )
      .run(
        ended,
        game.winner === null ? 'draw' : game.winner === 1 ? 'win' : 'loss',
        elapsed,
        game.history.length,
        id,
      );
  }
  onlineAbandon(id: string) {
    this.db
      .prepare("UPDATE analytics_games SET ended=?,result='abandoned' WHERE id=? AND ended IS NULL")
      .run(Date.now(), id);
  }
  recordCompleted(
    id: string,
    game: GameState,
    names: [string, string],
    mode: 'ai' | 'local' | 'online',
    elapsed: number,
    ended: number,
    results: { owner: string; player: 1 | 2 }[],
    ranked: boolean,
  ) {
    const p1 = results.find((r) => r.player === 1)?.owner ?? null;
    const p2 = mode === 'online' ? (results.find((r) => r.player === 2)?.owner ?? null) : null;
    this.db
      .prepare(
        `INSERT OR IGNORE INTO analytics_games(id,p1,p2,guest1,guest2,mode,difficulty,started,source)
      VALUES(?,?,?,?,?,?,?,?, 'legacy')`,
      )
      .run(
        id,
        p1,
        p2,
        mode === 'online' && !p1 ? names[0] : null,
        mode === 'online' && !p2 ? names[1] : null,
        mode === 'online' ? (ranked ? 'ranked' : 'lobby') : mode,
        mode === 'ai' ? 'unknown' : null,
        Math.max(0, ended - elapsed * 1000),
      );
    this.db
      .prepare(
        'UPDATE analytics_games SET ended=?,result=?,elapsed=?,moves=? WHERE id=? AND ended IS NULL',
      )
      .run(
        ended,
        game.winner === null ? 'draw' : game.winner === 1 ? 'win' : 'loss',
        elapsed,
        game.history.filter((m) => mode === 'online' || m.player === 1).length,
        id,
      );
  }
  renameOwner(previous: string, next: string) {
    for (const [table, column] of [
      ['analytics_sessions', 'owner'],
      ['analytics_sessions', 'identity'],
      ['analytics_games', 'p1'],
      ['analytics_games', 'p2'],
    ])
      this.db.prepare(`UPDATE ${table} SET ${column}=? WHERE ${column}=?`).run(next, previous);
  }
  deleteOwner(owner: string) {
    for (const [table, column] of [
      ['analytics_sessions', 'owner'],
      ['analytics_sessions', 'identity'],
      ['analytics_games', 'p1'],
      ['analytics_games', 'p2'],
    ])
      this.db.prepare(`UPDATE ${table} SET ${column}=NULL WHERE ${column}=?`).run(owner);
  }

  dashboard(filter: AnalyticsFilter, accounts: Account[], now = Date.now()): AnalyticsDashboard {
    const start = Date.parse(`${filter.from}T00:00:00+03:00`),
      end = Date.parse(`${filter.to}T00:00:00+03:00`) + 86400000;
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(filter.from) ||
      !/^\d{4}-\d{2}-\d{2}$/.test(filter.to) ||
      !Number.isFinite(start) ||
      !Number.isFinite(end) ||
      end <= start ||
      end - start > 366 * 86400000 ||
      new Date(start + 3 * 3600000).toISOString().slice(0, 10) !== filter.from ||
      new Date(end - 86400000 + 3 * 3600000).toISOString().slice(0, 10) !== filter.to ||
      !['all', ...modes].includes(filter.mode) ||
      !['all', 'desktop', 'mobile', 'tablet'].includes(filter.device)
    )
      throw new AuthError(400, 'Выберите корректный период до 366 дней и фильтры.');
    const device = filter.device === 'all' ? '' : ` AND device='${filter.device}'`;
    const mode = filter.mode === 'all' ? '' : ` AND mode='${filter.mode}'`;
    const visitWhere = `started>=? AND started<?${device}`;
    const gameWhere = `${visitWhere}${mode}`;
    const number = (v: unknown) => Number(v) || 0;
    const visitSummary = (a: number, b: number) =>
      this.db
        .prepare(
          `SELECT COUNT(*) sessions,COUNT(DISTINCT visitor) visitors,
      COALESCE(AVG(active_seconds),0) averageActiveSeconds FROM analytics_sessions WHERE ${visitWhere}`,
        )
        .get(a, b)!;
    const gameSummary = (a: number, b: number) =>
      this.db
        .prepare(
          `SELECT COUNT(*) started,
      COALESCE(SUM(result IN ('win','loss','draw')),0) completed,COALESCE(SUM(result='abandoned'),0) abandoned,
      COALESCE(SUM(ended IS NULL),0) unfinished,
      COALESCE(AVG(CASE WHEN result IN ('win','loss','draw') THEN elapsed END),0) averageGameSeconds
      FROM analytics_games WHERE ${gameWhere}`,
        )
        .get(a, b)!;
    const visits = visitSummary(start, end),
      games = gameSummary(start, end),
      duration = end - start;
    const previousVisits = visitSummary(start - duration, start),
      previousGames = gameSummary(start - duration, start);
    const returning = this.db
      .prepare(
        `SELECT COUNT(DISTINCT s.visitor) n FROM analytics_sessions s
      WHERE ${visitWhere} AND EXISTS(SELECT 1 FROM analytics_sessions old WHERE old.visitor=s.visitor AND old.started<?)`,
      )
      .get(start, end, start)!;
    const active = this.db
      .prepare(
        `SELECT COUNT(DISTINCT visitor) n FROM analytics_sessions WHERE last_seen>?${device}`,
      )
      .get(now - 90000)!;
    const actors = this.db
      .prepare(
        `SELECT COUNT(DISTINCT name) registered FROM (
      SELECT p1 name FROM analytics_games WHERE ${gameWhere} UNION ALL SELECT p2 FROM analytics_games WHERE ${gameWhere}) WHERE name IS NOT NULL`,
      )
      .get(start, end, start, end)!;
    const guests = this.db
      .prepare(
        `SELECT COUNT(DISTINCT identity) n FROM (
          SELECT guest1 identity FROM analytics_games WHERE ${gameWhere}
          UNION ALL SELECT guest2 FROM analytics_games WHERE ${gameWhere}) WHERE identity IS NOT NULL`,
      )
      .get(start, end, start, end)!;
    const dailyVisits = this.db
      .prepare(
        `SELECT date(started/1000,'unixepoch','+3 hours') date,COUNT(*) sessions,COUNT(DISTINCT visitor) visitors
      FROM analytics_sessions WHERE ${visitWhere} GROUP BY date`,
      )
      .all(start, end);
    const dailyGames = this.db
      .prepare(
        `SELECT date(started/1000,'unixepoch','+3 hours') date,COUNT(*) started,COALESCE(SUM(result IN ('win','loss','draw')),0) completed
      FROM analytics_games WHERE ${gameWhere} GROUP BY date`,
      )
      .all(start, end);
    const daily: AnalyticsDashboard['daily'] = [];
    for (let t = start; t < end; t += 86400000) {
      const date = new Date(t + 3 * 3600000).toISOString().slice(0, 10);
      const v = dailyVisits.find((r) => r.date === date),
        g = dailyGames.find((r) => r.date === date);
      daily.push({
        date,
        visitors: number(v?.visitors),
        sessions: number(v?.sessions),
        started: number(g?.started),
        completed: number(g?.completed),
        registrations: accounts.filter(
          (a) => a.createdAt && a.createdAt >= t && a.createdAt < t + 86400000,
        ).length,
      });
    }
    const modeRows = this.db
      .prepare(
        `SELECT mode,COUNT(*) started,SUM(result IN ('win','loss','draw')) completed,SUM(result='abandoned') abandoned,
      AVG(CASE WHEN result IN ('win','loss','draw') THEN elapsed END) averageSeconds FROM analytics_games WHERE ${gameWhere} GROUP BY mode`,
      )
      .all(start, end);
    const bots = this.db
      .prepare(
        `SELECT COALESCE(difficulty,'unknown') difficulty,COUNT(*) started,SUM(result IN ('win','loss','draw')) completed,
      SUM(result='win') wins,SUM(result='loss') losses,SUM(result='draw') draws,AVG(CASE WHEN result IN ('win','loss','draw') AND source!='history' THEN moves END) averageMoves,
      AVG(CASE WHEN result IN ('win','loss','draw') THEN elapsed END) averageSeconds FROM analytics_games WHERE ${gameWhere} AND mode='ai' GROUP BY difficulty`,
      )
      .all(start, end);
    const breakdown = (column: 'device' | 'browser' | 'source') =>
      this.db
        .prepare(
          `SELECT ${column} name,COUNT(*) sessions,COUNT(DISTINCT visitor) visitors
      FROM analytics_sessions WHERE ${visitWhere} GROUP BY ${column} ORDER BY sessions DESC LIMIT 12`,
        )
        .all(start, end)
        .map((r) => ({
          name: String(r.name),
          sessions: number(r.sessions),
          visitors: number(r.visitors),
        }));
    const playerRows = this.db
      .prepare(
        `WITH participation AS (
      SELECT p1 username,mode,difficulty,started,ended,result FROM analytics_games WHERE ${gameWhere}
      UNION ALL SELECT p2 username,mode,difficulty,started,ended,CASE result WHEN 'win' THEN 'loss' WHEN 'loss' THEN 'win' ELSE result END
      FROM analytics_games WHERE ${gameWhere} AND p2 IS NOT p1)
      SELECT username,COUNT(*) games,SUM(result IN ('win','loss','draw')) completed,
      SUM(result='win' AND mode!='local') wins,SUM(result='loss' AND mode!='local') losses,SUM(result='draw' AND mode!='local') draws,
      SUM(mode='ai') ai,SUM(mode='local') local,SUM(mode='level') level,SUM(mode='ranked') ranked,SUM(mode='lobby') lobby,MAX(started) lastPlayedAt
      FROM participation WHERE username IS NOT NULL GROUP BY username ORDER BY games DESC,username LIMIT 200`,
      )
      .all(start, end, start, end);
    const playerBots = this.db
      .prepare(
        `SELECT p1 username,COALESCE(difficulty,'unknown') difficulty,SUM(result='win') wins,SUM(result='loss') losses,SUM(result='draw') draws
      FROM analytics_games WHERE ${gameWhere} AND mode='ai' AND p1 IS NOT NULL GROUP BY p1,difficulty`,
      )
      .all(start, end);
    const levelRows = this.db
      .prepare(
        `SELECT level,COUNT(*) started,SUM(result IN ('win','loss','draw')) completed,SUM(result='win') wins,SUM(result='loss') losses,
      MIN(CASE WHEN result='win' THEN moves END) bestMoves FROM analytics_games WHERE ${gameWhere} AND mode='level' GROUP BY level ORDER BY level`,
      )
      .all(start, end);
    return {
      generatedAt: now,
      collectionStartedAt: number(
        this.db.prepare("SELECT value FROM analytics_meta WHERE key='collection_started'").get()
          ?.value,
      ),
      filter,
      summary: {
        visitors: number(visits.visitors),
        sessions: number(visits.sessions),
        returningVisitors: number(returning.n),
        activeNow: number(active.n),
        averageActiveSeconds: number(visits.averageActiveSeconds),
        started: number(games.started),
        completed: number(games.completed),
        abandoned: number(games.abandoned),
        unfinished: number(games.unfinished),
        averageGameSeconds: number(games.averageGameSeconds),
        registeredPlayers: number(actors.registered),
        guestPlayers: number(guests.n),
        previousVisitors: number(previousVisits.visitors),
        previousStarted: number(previousGames.started),
      },
      accounts: {
        total: accounts.length,
        new: accounts.filter((a) => a.createdAt && a.createdAt >= start && a.createdAt < end)
          .length,
        verified: accounts.filter((a) => a.emailVerified).length,
        blocked: accounts.filter((a) => a.disabled).length,
      },
      daily,
      modes: modes.map((m) => {
        const r = modeRows.find((r) => r.mode === m);
        return {
          mode: m,
          started: number(r?.started),
          completed: number(r?.completed),
          abandoned: number(r?.abandoned),
          averageSeconds: number(r?.averageSeconds),
        };
      }),
      bots: bots.map((r) => ({
        difficulty: String(r.difficulty),
        started: number(r.started),
        completed: number(r.completed),
        wins: number(r.wins),
        losses: number(r.losses),
        draws: number(r.draws),
        averageMoves: number(r.averageMoves),
        averageSeconds: number(r.averageSeconds),
      })),
      devices: breakdown('device'),
      browsers: breakdown('browser'),
      sources: breakdown('source'),
      players: playerRows.map((r) => ({
        username: String(r.username),
        games: number(r.games),
        completed: number(r.completed),
        wins: number(r.wins),
        losses: number(r.losses),
        draws: number(r.draws),
        ai: number(r.ai),
        local: number(r.local),
        level: number(r.level),
        ranked: number(r.ranked),
        lobby: number(r.lobby),
        lastPlayedAt: number(r.lastPlayedAt),
        favoriteMode: [...modes].sort((a, b) => number(r[b]) - number(r[a]))[0],
        bots: playerBots
          .filter((b) => b.username === r.username)
          .map((b) => ({
            difficulty: String(b.difficulty),
            wins: number(b.wins),
            losses: number(b.losses),
            draws: number(b.draws),
          })),
      })),
      levels: levelRows.map((r) => ({
        level: number(r.level),
        started: number(r.started),
        completed: number(r.completed),
        wins: number(r.wins),
        losses: number(r.losses),
        bestMoves: r.bestMoves === null ? null : number(r.bestMoves),
      })),
    };
  }
}
