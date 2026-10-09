import { existsSync } from 'node:fs';
import { Worker } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';
import {
  dailyDate,
  dailyExpiresAt,
  isDailyChallenge,
  type DailyChallenge,
} from '../src/game/daily.ts';
import { AuthError } from './auth.ts';
import { StatisticsStore } from './statistics.ts';
import type { DailyMove } from './dailyReplay.ts';

type Task =
  | { type: 'generate'; date: string }
  | { type: 'verify'; challenge: DailyChallenge; moves: DailyMove[] };

/** A single bounded worker keeps generation and replay away from active online games. */
class DailyComputer {
  private worker: Worker | null = null;
  private pending = 0;
  private tail: Promise<unknown> = Promise.resolve();
  private closed = false;

  run(task: Task): Promise<unknown> {
    if (this.closed) return Promise.reject(new AuthError(503, 'Сервер перезапускается.'));
    if (this.pending >= 8)
      return Promise.reject(
        new AuthError(429, 'Проверка результатов занята. Попробуйте через несколько секунд.'),
      );
    this.pending++;
    const result = this.tail.then(() => this.execute(task));
    this.tail = result.catch(() => undefined);
    return result.finally(() => this.pending--);
  }

  private execute(task: Task): Promise<unknown> {
    if (this.closed) return Promise.reject(new AuthError(503, 'Сервер перезапускается.'));
    const built = new URL('./daily.worker.js', import.meta.url);
    const development = !existsSync(built);
    this.worker ??= new Worker(
      fileURLToPath(development ? new URL('./daily.worker.ts', import.meta.url) : built),
      {
        execArgv: development ? ['--import', 'tsx'] : [],
      },
    );
    const worker = this.worker;
    return new Promise((resolve, reject) => {
      const cleanup = () => {
        clearTimeout(timer);
        worker.off('message', message);
        worker.off('error', failed);
        worker.off('exit', exited);
      };
      const failed = (error: Error) => {
        cleanup();
        this.worker = null;
        void worker.terminate();
        reject(
          new AuthError(
            503,
            `Не удалось ${task.type === 'generate' ? 'подготовить задачу дня' : 'проверить результат'}. Попробуйте снова.`,
          ),
        );
        if (process.env.NODE_ENV !== 'test') console.error('Daily worker:', error.message);
      };
      const exited = () => failed(new Error('Daily worker stopped'));
      const message = (response: { ok: boolean; value?: unknown; error?: string }) => {
        cleanup();
        if (response.ok) resolve(response.value);
        else
          reject(
            new AuthError(
              task.type === 'verify' ? 400 : 503,
              task.type === 'verify'
                ? 'Последовательность ходов не подтверждает победу.'
                : 'Не удалось подготовить задачу дня. Попробуйте снова.',
            ),
          );
      };
      const timer = setTimeout(
        () => failed(new Error('Daily worker timed out')),
        task.type === 'generate' ? 120_000 : 30_000,
      );
      worker.once('message', message);
      worker.once('error', failed);
      worker.once('exit', exited);
      worker.postMessage(task);
    });
  }

  async close() {
    this.closed = true;
    if (this.worker) await this.worker.terminate();
    this.worker = null;
    await this.tail;
  }
}

export interface DailyServiceOptions {
  now?: () => number;
  /** Dependency injection for isolated tests; production always uses the dedicated worker. */
  generate?: (date: string) => Promise<DailyChallenge>;
  verify?: (challenge: DailyChallenge, moves: DailyMove[]) => Promise<number>;
}

export class DailyService {
  private readonly computer = new DailyComputer();
  private readonly preparing = new Map<string, Promise<DailyChallenge>>();
  private readonly verified = new Map<string, number>();
  private readonly now: () => number;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private stopped = false;
  private started = false;

  constructor(
    private statistics: StatisticsStore,
    private options: DailyServiceOptions = {},
  ) {
    this.now = options.now ?? Date.now;
  }

  /** Prepare today and tomorrow without waiting for a visitor, then roll over at Moscow midnight. */
  start() {
    if (this.started || this.stopped) return;
    this.started = true;
    const prepare = async () => {
      if (this.stopped) return;
      const date = dailyDate(this.now());
      let failed = false;
      try {
        await this.challenge(date);
        if (!this.stopped) await this.challenge(dailyDate(dailyExpiresAt(date) + 1));
      } catch (error) {
        failed = true;
        if (!this.stopped)
          console.error('Daily preparation:', error instanceof Error ? error.message : error);
      } finally {
        if (!this.stopped) {
          const midnight = Math.max(
            1000,
            dailyExpiresAt(dailyDate(this.now())) - this.now() + 1000,
          );
          const delay = failed ? Math.min(5 * 60_000, midnight) : midnight;
          this.timer = setTimeout(() => void prepare(), delay);
          this.timer.unref();
        }
      }
    };
    void prepare();
  }

  private challenge(date: string): Promise<DailyChallenge> {
    const stored = this.statistics.dailyChallenge(date);
    if (stored) return Promise.resolve(stored);
    const existing = this.preparing.get(date);
    if (existing) return existing;
    const prepare = (
      this.options.generate
        ? this.options.generate(date)
        : (this.computer.run({ type: 'generate', date }) as Promise<DailyChallenge>)
    )
      .then((challenge) => {
        if (!isDailyChallenge(challenge) || challenge.date !== date)
          throw new AuthError(503, 'Некорректная задача дня.');
        return this.statistics.saveDailyChallenge(challenge);
      })
      .finally(() => this.preparing.delete(date));
    this.preparing.set(date, prepare);
    return prepare;
  }

  async read(owner: string | null, usernames: string[]) {
    let now = this.now();
    let challenge = await this.challenge(dailyDate(now));
    // Generation started just before midnight must not serve yesterday's position.
    now = this.now();
    if (challenge.date !== dailyDate(now)) challenge = await this.challenge(dailyDate(now));
    return {
      username: owner,
      challenge,
      leaderboard: this.statistics.dailyStandings(challenge.date, usernames).slice(0, 100),
      ownBest: this.statistics.dailyBest(challenge.date, owner),
      now: this.now(),
    };
  }

  async submit(
    owner: string,
    usernames: string[],
    raw: unknown,
    accountIsCurrent: () => boolean = () => true,
  ) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw))
      throw new AuthError(400, 'Некорректный результат.');
    const data = raw as Record<string, unknown>;
    if (data.owner !== owner) throw new AuthError(403, 'Аккаунт изменился. Обновите страницу.');
    if (
      typeof data.challengeId !== 'string' ||
      data.challengeId.length > 100 ||
      !Array.isArray(data.moves) ||
      !data.moves.length ||
      data.moves.length > 63
    )
      throw new AuthError(400, 'Некорректная последовательность ходов.');
    const moves = data.moves.map((value: unknown) => {
      if (!value || typeof value !== 'object' || Array.isArray(value))
        throw new AuthError(400, 'Некорректный ход.');
      const move = value as Record<string, unknown>;
      if (
        !Number.isInteger(move.x) ||
        !Number.isInteger(move.y) ||
        Number(move.x) < 0 ||
        Number(move.x) > 4 ||
        Number(move.y) < 0 ||
        Number(move.y) > 4 ||
        Object.keys(move).some((key) => key !== 'x' && key !== 'y')
      )
        throw new AuthError(400, 'Некорректный ход.');
      return { x: Number(move.x), y: Number(move.y) };
    });
    const challenge = await this.challenge(dailyDate(this.now()));
    if (data.challengeId !== challenge.id)
      throw new AuthError(409, 'Эта задача дня завершилась. Откройте новую задачу.');
    const key = `${challenge.id}:${JSON.stringify(moves)}`;
    let count = this.verified.get(key);
    if (count === undefined) {
      try {
        count = this.options.verify
          ? await this.options.verify(challenge, moves)
          : ((await this.computer.run({ type: 'verify', challenge, moves })) as number);
      } catch (error) {
        if (error instanceof AuthError) throw error;
        throw new AuthError(400, 'Последовательность ходов не подтверждает победу.');
      }
      if (this.verified.size >= 256) this.verified.clear();
      this.verified.set(key, count);
    }
    if (challenge.date !== dailyDate(this.now()) || this.now() >= challenge.expiresAt)
      throw new AuthError(409, 'Эта задача дня завершилась. Откройте новую задачу.');
    if (!accountIsCurrent()) throw new AuthError(403, 'Аккаунт изменился. Обновите страницу.');
    if (!usernames.includes(owner))
      throw new AuthError(403, 'Аккаунт недоступен для таблицы результатов.');
    this.statistics.saveDailyResult(challenge.date, owner, count, this.now(), moves);
    const standings = this.statistics.dailyStandings(challenge.date, usernames);
    return {
      username: owner,
      challenge,
      ownBest: this.statistics.dailyBest(challenge.date, owner)!,
      rank: standings.find((row) => row.username === owner)!.rank,
      leaderboard: standings.slice(0, 100),
      now: this.now(),
    };
  }

  async close() {
    this.stopped = true;
    clearTimeout(this.timer);
    await this.computer.close();
    await Promise.allSettled(this.preparing.values());
  }
}
