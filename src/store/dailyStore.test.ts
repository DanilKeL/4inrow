// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { makeMove, replay } from '../game/core';
import { chooseMove } from '../game/ai/search';
import { DAILY_BOT_OPTIONS, dailyExpiresAt } from '../game/daily';
import { getLevel } from '../game/levels';
import solutions from '../game/levels/solutions.json';

const challenge = {
  id: 'daily-1-2026-10-09',
  date: '2026-10-09',
  version: 1 as const,
  preset: getLevel(37)!.preset,
  expiresAt: dailyExpiresAt('2026-10-09'),
};
const moves = solutions.find((level) => level.id === 37)!.solution;
function victory() {
  let game = replay(challenge.preset);
  for (const move of moves) {
    const human = makeMove(game, move.x, move.y);
    if (!human.valid) throw new Error('Illegal fixture move');
    game = human.state;
    if (game.status !== 'playing') break;
    const bot = chooseMove(game, 'medium', DAILY_BOT_OPTIONS)!;
    const reply = makeMove(game, bot.x, bot.y);
    if (!reply.valid) throw new Error('Illegal fixture bot move');
    game = reply.state;
  }
  expect(game.winner).toBe(1);
  return game;
}
const response = () => ({
  username: 'Alice',
  challenge,
  ownBest: moves.length,
  leaderboard: [{ rank: 1, username: 'Alice', moves: moves.length, completedAt: 1 }],
  rank: 1,
  now: challenge.expiresAt - 60000,
});
async function setup() {
  const { useAccount } = await import('./accountStore');
  useAccount.setState({ username: 'Alice', identityReady: true });
  const { useDaily } = await import('./dailyStore');
  return { useDaily, useAccount };
}
let online = true;
beforeEach(() => {
  vi.resetModules();
  localStorage.clear();
  online = true;
  vi.spyOn(navigator, 'onLine', 'get').mockImplementation(() => online);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
describe('verified daily result outbox', () => {
  it('sends only human columns and expected owner, then restores the server best after resume', async () => {
    const fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify(response())));
    vi.stubGlobal('fetch', fetch);
    const { useDaily } = await setup();
    useDaily.getState().saveWin('daily-run', challenge, victory(), 'Alice');
    await useDaily.getState().flush();
    expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({
      owner: 'Alice',
      challengeId: challenge.id,
      moves,
    });
    expect(useDaily.getState().result).toMatchObject({
      id: 'daily-run',
      status: 'verified',
      rank: 1,
    });
    expect(useDaily.getState().challenge).toEqual(challenge);
    expect(useDaily.getState().ownBest).toBe(moves.length);
    expect(useDaily.getState().pending).toEqual([]);
  });
  it('keeps a failed sequence across browser reload and submits it on reconnection', async () => {
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(new TypeError('Offline'))
      .mockResolvedValue(new Response(JSON.stringify(response())));
    vi.stubGlobal('fetch', fetch);
    const { useDaily } = await setup();
    useDaily.getState().saveWin('daily-run', challenge, victory(), 'Alice');
    await useDaily.getState().flush();
    expect(useDaily.getState().result?.status).toBe('failed');
    expect(useDaily.getState().ownBest).toBeNull();
    expect(JSON.parse(localStorage.getItem('four-cubed-daily-v1')!)).toHaveLength(1);
    vi.resetModules();
    const reloaded = await setup();
    expect(reloaded.useDaily.getState().pending).toHaveLength(1);
    await reloaded.useDaily.getState().flush();
    expect(reloaded.useDaily.getState().pending).toEqual([]);
    expect(reloaded.useDaily.getState().ownBest).toBe(moves.length);
  });
  it('does not submit guest wins or another account pending result', async () => {
    const fetch = vi.fn();
    vi.stubGlobal('fetch', fetch);
    const { useDaily, useAccount } = await setup();
    useDaily.getState().saveWin('guest-run', challenge, victory(), null);
    expect(useDaily.getState().result?.status).toBe('guest');
    expect(fetch).not.toHaveBeenCalled();
    online = false;
    useDaily.getState().saveWin('alice-run', challenge, victory(), 'Alice');
    useAccount.setState({ username: 'Bob', identityReady: false });
    useAccount.setState({ identityReady: true });
    online = true;
    await useDaily.getState().flush();
    expect(fetch).not.toHaveBeenCalled();
    expect(useDaily.getState().pending[0].owner).toBe('Alice');
    expect(useDaily.getState().ownBest).toBeNull();
  });
  it('retains a session mismatch for its owner but drops an expired day result', async () => {
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ error: 'Аккаунт изменился.' }), { status: 403 }),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ error: 'Задача завершилась.' }), { status: 409 }),
      );
    vi.stubGlobal('fetch', fetch);
    const { useDaily } = await setup();
    useDaily.getState().saveWin('daily-run', challenge, victory(), 'Alice');
    await useDaily.getState().flush();
    expect(useDaily.getState().pending).toHaveLength(1);
    expect(useDaily.getState().ownBest).toBeNull();
    await useDaily.getState().flush();
    expect(useDaily.getState().pending).toHaveLength(0);
    expect(useDaily.getState().result).toMatchObject({
      status: 'failed',
      error: 'Задача завершилась.',
    });
  });
});
