import { afterEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { AddressInfo } from 'node:net';
import { DailyService } from './dailyService';
import { StatisticsStore } from './statistics';
import { createOnlineServer } from './app';
import { dailyExpiresAt, type DailyChallenge } from '../src/game/daily';
import { getLevel } from '../src/game/levels';
import solutions from '../src/game/levels/solutions.json';
import { verifyDailyResult } from './dailyReplay';

const date = '2026-10-09';
const challenge = (day = date): DailyChallenge => ({
  id: `daily-1-${day}`,
  date: day,
  version: 1,
  preset: getLevel(5)!.preset,
  expiresAt: dailyExpiresAt(day),
});
const solution = solutions.find((level) => level.id === 5)!.solution;
const stores: StatisticsStore[] = [];
const services: DailyService[] = [];
const servers: ReturnType<typeof createOnlineServer>[] = [];
const dirs: string[] = [];
afterEach(async () => {
  await Promise.all(servers.splice(0).map((server) => server.close()));
  await Promise.all(services.splice(0).map((service) => service.close()));
  for (const store of stores.splice(0)) store.close();
  for (const dir of dirs.splice(0)) {
    expect(resolve(dir).startsWith(resolve(tmpdir()))).toBe(true);
    rmSync(dir, { recursive: true, force: true });
  }
  vi.useRealTimers();
});
function open(file: string | null = null) {
  const store = new StatisticsStore(file);
  stores.push(store);
  return store;
}
function service(
  store: StatisticsStore,
  now: () => number = () => Date.parse(`${date}T12:00:00Z`),
) {
  const daily = new DailyService(store, {
    now,
    generate: async (day) => challenge(day),
    verify: async (position, moves) => verifyDailyResult(position, moves),
  });
  services.push(daily);
  return daily;
}

describe('server daily challenge verification', () => {
  it('automatically prepares today and tomorrow, then the next date at Moscow midnight', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(`${date}T20:59:59Z`));
    const generated: string[] = [];
    const daily = new DailyService(open(), {
      generate: async (day) => {
        generated.push(day);
        return challenge(day);
      },
    });
    services.push(daily);
    daily.start();
    daily.start();
    await vi.advanceTimersByTimeAsync(0);
    expect(generated).toEqual([date, '2026-10-10']);
    await vi.advanceTimersByTimeAsync(2000);
    expect(generated).toEqual([date, '2026-10-10', '2026-10-11']);
    expect((await daily.read(null, [])).challenge.date).toBe('2026-10-10');
  });

  it('verifies a real sequence in the dedicated Node worker', async () => {
    const store = open();
    store.saveDailyChallenge(challenge());
    const daily = new DailyService(store, { now: () => Date.parse(`${date}T12:00:00Z`) });
    services.push(daily);
    expect(
      await daily.submit('Alice', ['Alice'], {
        owner: 'Alice',
        challengeId: challenge().id,
        moves: solution,
      }),
    ).toMatchObject({ ownBest: solution.length, rank: 1 });
  });
  it('recomputes deterministic bot turns and rejects unfinished, illegal and padded histories', () => {
    expect(verifyDailyResult(challenge(), solution)).toBe(solution.length);
    expect(() => verifyDailyResult(challenge(), solution.slice(0, -1))).toThrow(/unfinished/i);
    expect(() => verifyDailyResult(challenge(), [...solution, { x: 0, y: 0 }])).toThrow();
    expect(() => verifyDailyResult(challenge(), [{ x: 10, y: 2 }])).toThrow();
    const altered = [{ x: 0, y: 0 }, ...solution.slice(1)];
    expect(() => verifyDailyResult(challenge(), altered)).toThrow();
  });

  it('shares one generation across concurrent requests and persists the exact preset across restart', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'four-daily-'));
    dirs.push(dir);
    const file = join(dir, 'statistics.sqlite');
    let generated = 0;
    const first = new DailyService(open(file), {
      now: () => Date.parse(`${date}T12:00:00Z`),
      generate: async (day) => {
        generated++;
        await new Promise((resolve) => setTimeout(resolve, 15));
        return challenge(day);
      },
    });
    services.push(first);
    const replies = await Promise.all(Array.from({ length: 10 }, () => first.read(null, [])));
    expect(generated).toBe(1);
    expect(
      replies.every((reply) => JSON.stringify(reply.challenge) === JSON.stringify(challenge())),
    ).toBe(true);
    const next = new DailyService(open(file), {
      now: () => Date.parse(`${date}T13:00:00Z`),
      generate: async () => {
        throw new Error('Must read SQLite');
      },
    });
    services.push(next);
    expect((await next.read(null, [])).challenge).toEqual(challenge());
    expect(JSON.stringify(await next.read(null, []))).not.toMatch(/solution|quality/);
  });

  it('keeps each player best and first-achieved timestamp, ranks ties and integrates rename/delete', async () => {
    const store = open();
    store.saveDailyChallenge(challenge());
    store.saveDailyResult(date, 'Bob', 5, 100, [{ x: 0, y: 0 }]);
    store.saveDailyResult(date, 'Alice', 5, 101, [{ x: 1, y: 0 }]);
    store.saveDailyResult(date, 'Hidden', 1, 1, [{ x: 1, y: 0 }]);
    store.saveDailyResult(date, 'Bob', 6, 200, [{ x: 0, y: 1 }]);
    store.saveDailyResult(date, 'Bob', 5, 201, [{ x: 0, y: 1 }]);
    expect(store.dailyStandings(date, ['Alice', 'Bob'])).toEqual([
      { rank: 1, username: 'Bob', moves: 5, completedAt: 100 },
      { rank: 2, username: 'Alice', moves: 5, completedAt: 101 },
    ]);
    store.saveDailyResult(date, 'Alice', 3, 300, [{ x: 0, y: 1 }]);
    expect(store.dailyStandings(date, ['Alice', 'Bob'])[0]).toMatchObject({
      username: 'Alice',
      moves: 3,
      completedAt: 300,
    });
    store.renameOwner('Alice', 'Renamed');
    expect(store.dailyBest(date, 'Renamed')).toBe(3);
    store.deleteOwner('Renamed');
    expect(store.dailyBest(date, 'Renamed')).toBeNull();
    expect(store.dailyStandings(date, ['Renamed', 'Bob'])).toHaveLength(1);
  });

  it('changes the challenge at Moscow midnight and rejects a result when verification crosses midnight', async () => {
    let now = dailyExpiresAt(date) - 1;
    const store = open();
    const daily = service(store, () => now);
    expect((await daily.read(null, [])).challenge.date).toBe(date);
    now++;
    expect((await daily.read(null, [])).challenge.date).toBe('2026-10-10');
    await expect(
      daily.submit('Alice', ['Alice'], {
        owner: 'Alice',
        challengeId: challenge().id,
        moves: solution,
      }),
    ).rejects.toMatchObject({ status: 409 });
    now = dailyExpiresAt(date) - 1;
    const crossing = new DailyService(store, {
      now: () => now,
      generate: async (day) => challenge(day),
      verify: async () => {
        now++;
        return solution.length;
      },
    });
    services.push(crossing);
    await expect(
      crossing.submit('Alice', ['Alice'], {
        owner: 'Alice',
        challengeId: challenge().id,
        moves: solution,
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(store.dailyBest(date, 'Alice')).toBeNull();
  });

  it('rechecks account identity after CPU verification and leaves no result for a deleted account', async () => {
    const store = open();
    const daily = service(store);
    await expect(
      daily.submit('Alice', ['Alice', 'Bob'], {
        owner: 'Bob',
        challengeId: challenge().id,
        moves: solution,
      }),
    ).rejects.toMatchObject({ status: 403 });
    expect(store.dailyBest(date, 'Alice')).toBeNull();
    expect(store.dailyBest(date, 'Bob')).toBeNull();
    await expect(
      daily.submit(
        'Alice',
        ['Alice'],
        { owner: 'Alice', challengeId: challenge().id, moves: solution },
        () => false,
      ),
    ).rejects.toMatchObject({ status: 403 });
    expect(store.dailyBest(date, 'Alice')).toBeNull();
  });
});

describe('daily HTTP API', () => {
  async function start() {
    const server = createOnlineServer({
      staticDir: null,
      authFile: null,
      statsFile: null,
      mailer: null,
      daily: {
        now: () => Date.parse(`${date}T12:00:00Z`),
        generate: async (day) => challenge(day),
        verify: async (position, moves) => verifyDailyResult(position, moves),
      },
    });
    servers.push(server);
    await new Promise<void>((resolve) => server.httpServer.listen(0, '127.0.0.1', resolve));
    const url = `http://127.0.0.1:${(server.httpServer.address() as AddressInfo).port}`;
    const post = (path: string, body: unknown, cookie?: string, origin?: string) =>
      fetch(url + path, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(cookie ? { Cookie: cookie } : {}),
          ...(origin ? { Origin: origin } : {}),
        },
        body: JSON.stringify(body),
      });
    const registered = await post('/auth/register', {
      username: 'DailyPlayer',
      password: 'daily-test-password',
    });
    expect(registered.status).toBe(200);
    const cookie = registered.headers.get('set-cookie')!.split(';')[0];
    return { url, post, cookie };
  }

  it('publishes the same position for guests, accepts a verified victory and rejects claimed/illegal results', async () => {
    const { url, post, cookie } = await start();
    const guest = await fetch(url + '/daily');
    expect(guest.status).toBe(200);
    expect(guest.headers.get('cache-control')).toBe('no-store');
    expect(await guest.json()).toMatchObject({
      challenge: challenge(),
      ownBest: null,
      leaderboard: [],
    });
    const body = { owner: 'DailyPlayer', challengeId: challenge().id, moves: solution };
    expect((await post('/daily/results', body)).status).toBe(401);
    expect(
      (
        await post(
          '/daily/results',
          { ...body, moves: solution.slice(0, -1), winner: 1, count: 1 },
          cookie,
        )
      ).status,
    ).toBe(400);
    expect(
      (await post('/daily/results', { ...body, moves: [{ x: 2, y: 1, player: 1 }] }, cookie))
        .status,
    ).toBe(400);
    expect(
      (await post('/daily/results', { ...body, challengeId: 'daily-1-2026-10-08' }, cookie)).status,
    ).toBe(409);
    expect((await post('/daily/results', body, cookie, 'https://evil.example')).status).toBe(403);
    const accepted = await post('/daily/results', { ...body, movesCount: 1, winner: 2 }, cookie);
    expect(accepted.status).toBe(200);
    expect(await accepted.json()).toMatchObject({
      ownBest: solution.length,
      rank: 1,
      leaderboard: [{ username: 'DailyPlayer', moves: solution.length, rank: 1 }],
    });
    expect(
      await (await fetch(url + '/daily', { headers: { Cookie: cookie } })).json(),
    ).toMatchObject({ ownBest: solution.length });
  });

  it('bounds CPU submissions per account and rejects oversized requests', async () => {
    const { post, cookie } = await start();
    expect(
      (
        await post(
          '/daily/results',
          {
            owner: 'DailyPlayer',
            challengeId: challenge().id,
            moves: solution,
            padding: 'a'.repeat(9000),
          },
          cookie,
        )
      ).status,
    ).toBe(413);
    for (let attempt = 0; attempt < 19; attempt++)
      expect(
        (
          await post(
            '/daily/results',
            { owner: 'DailyPlayer', challengeId: challenge().id, moves: [] },
            cookie,
          )
        ).status,
      ).toBe(400);
    expect(
      (
        await post(
          '/daily/results',
          { owner: 'DailyPlayer', challengeId: challenge().id, moves: solution },
          cookie,
        )
      ).status,
    ).toBe(429);
  });
});
