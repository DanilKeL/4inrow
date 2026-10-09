// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { replay } from '../game/core';
import type { MoveCandidate } from '../game/ai';
import { chooseMove } from '../game/ai/search';
import { getLevel, levelPosition, levelMoveCount, LEVEL_BOT_OPTIONS } from '../game/levels';
import solutions from '../game/levels/solutions.json';
import { useLevelProgress } from './levelStore';
import { useMatchHistory } from './matchHistory';
import { readSavedGame } from './savedGame';
import { useAccount } from './accountStore';
import { DAILY_BOT_OPTIONS, dailyExpiresAt } from '../game/daily';

const mocked = vi.hoisted(() => ({
  bot: vi.fn(),
  sound: vi.fn(),
  settings: { sound: true, animations: true, xrayDefault: false },
}));
vi.mock('../game/ai', () => ({ requestBotMove: mocked.bot }));
vi.mock('../audio/sound', () => ({ playSound: mocked.sound }));
vi.mock('./settingsStore', () => ({ useSettings: { getState: () => mocked.settings } }));

import { displayedGame, useGame } from './gameStore';

const state = () => useGame.getState();
const winMoves = [
  { x: 0, y: 0 },
  { x: 0, y: 4 },
  { x: 1, y: 0 },
  { x: 1, y: 4 },
  { x: 2, y: 0 },
  { x: 2, y: 4 },
  { x: 3, y: 0 },
];
function pendingBot() {
  let resolve!: (move: MoveCandidate | null) => void;
  let reject!: (reason: Error) => void;
  mocked.bot.mockImplementationOnce(
    () =>
      new Promise<MoveCandidate | null>((yes, no) => {
        resolve = yes;
        reject = no;
      }),
  );
  return {
    resolve: (move: MoveCandidate | null) => resolve(move),
    reject: (error: Error) => reject(error),
  };
}
async function beginBotTurn() {
  state().start('ai');
  state().place(2, 2);
  await vi.advanceTimersByTimeAsync(440);
  expect(state().phase).toBe('ai-thinking');
}

beforeEach(() => {
  vi.useFakeTimers();
  mocked.bot.mockReset();
  mocked.bot.mockResolvedValue({ x: 0, y: 0 });
  mocked.sound.mockReset();
  mocked.settings.animations = true;
  mocked.settings.sound = true;
  state().start('local');
});
afterEach(() => {
  state().menu();
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('input and animation coordination', () => {
  it('uses the fixed daily bot, resumes its preset and restarts without allowing undo', async () => {
    useAccount.setState({ username: null });
    const preset = getLevel(37)!;
    const challenge = {
      id: 'daily-1-2026-10-09',
      date: '2026-10-09',
      version: 1 as const,
      preset: preset.preset,
      expiresAt: dailyExpiresAt('2026-10-09'),
    };
    mocked.bot.mockImplementation((game) =>
      Promise.resolve(chooseMove(game, 'medium', DAILY_BOT_OPTIONS)),
    );
    state().startDaily(challenge);
    const original = state().game;
    state().undoMove();
    expect(state().game).toBe(original);
    const first = solutions.find((level) => level.id === 37)!.solution[0];
    state().place(first.x, first.y);
    await vi.advanceTimersByTimeAsync(1000);
    expect(mocked.bot).toHaveBeenCalledWith(
      expect.anything(),
      'medium',
      expect.anything(),
      DAILY_BOT_OPTIONS,
    );
    const played = state().game;
    state().menu();
    state().resumeSavedGame();
    expect(state().mode).toBe('daily');
    expect(state().dailyChallenge).toEqual(challenge);
    expect(state().game).toEqual(played);
    state().undoMove();
    expect(state().game).toEqual(played);
    state().restart();
    expect(state().game).toEqual(original);
  });
  it('plays a preset with deterministic replies and saves only human moves as a separate record', async () => {
    mocked.settings.animations = false;
    useLevelProgress.setState({ best: {}, guestBest: {}, accounts: {} });
    const save = vi.spyOn(useMatchHistory.getState(), 'save');
    mocked.bot.mockImplementation((game, difficulty, _signal, options) =>
      Promise.resolve(chooseMove(game, difficulty, options)),
    );
    state().start('ai', 'hard');
    state().startLevel(9);
    const level = getLevel(9)!;
    expect(state().game).toEqual(levelPosition(level));
    expect(levelMoveCount(state().game, level)).toBe(0);
    for (const move of solutions.find((s) => s.id === 9)!.solution) {
      state().place(move.x, move.y);
      await vi.advanceTimersByTimeAsync(1000);
    }
    expect(state().phase).toBe('victory');
    expect(state().game.winner).toBe(1);
    expect(useLevelProgress.getState().best[9]).toBe(3);
    expect(mocked.bot.mock.calls[0][1]).toBe('medium');
    expect(mocked.bot.mock.calls[0][3]).toEqual(LEVEL_BOT_OPTIONS);
    expect(save).not.toHaveBeenCalled();
    state().restart();
    expect(state().game).toEqual(levelPosition(level));
    expect(state().levelBestBefore).toBe(3);
    expect(state().difficulty).toBe('hard');
    state().undoMove();
    expect(state().game).toEqual(levelPosition(level));
  });
  it('cancels a level reply on restart and rejects an unknown level', async () => {
    mocked.settings.animations = false;
    state().startLevel(9);
    const initial = state().game;
    state().startLevel(999);
    expect(state().game).toBe(initial);
    const pending = pendingBot();
    const move = solutions.find((s) => s.id === 9)!.solution[0];
    state().place(move.x, move.y);
    await vi.advanceTimersByTimeAsync(80);
    const signal = mocked.bot.mock.calls[0][2] as AbortSignal;
    state().restart();
    expect(signal.aborted).toBe(true);
    pending.resolve({ x: 0, y: 0 });
    await vi.advanceTimersByTimeAsync(1000);
    expect(state().game).toEqual(initial);
    expect(state().phase).toBe('playing');
  });
  it('locks an immediate second click until the first animation settles', async () => {
    state().place(2, 2);
    state().place(3, 3);
    expect(state().game.history).toHaveLength(1);
    expect(state().phase).toBe('animating');
    await vi.advanceTimersByTimeAsync(439);
    expect(state().phase).toBe('animating');
    await vi.advanceTimersByTimeAsync(1);
    expect(state().phase).toBe('playing');
    state().place(3, 3);
    expect(state().game.history).toHaveLength(2);
  });

  it('still locks input with animations disabled', async () => {
    mocked.settings.animations = false;
    state().place(2, 2);
    state().place(2, 2);
    expect(state().game.history).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(80);
    expect(state().phase).toBe('playing');
  });

  it('keeps a committed piece when paused during animation and resumes its turn', async () => {
    state().place(2, 2);
    state().pause();
    state().place(3, 3);
    await vi.advanceTimersByTimeAsync(1000);
    expect(state().phase).toBe('paused');
    expect(state().game.history).toHaveLength(1);
    expect(mocked.sound).not.toHaveBeenCalled();
    state().resume();
    expect(state().phase).toBe('playing');
    expect(state().game.currentPlayer).toBe(2);
  });

  it('does not settle an old animation after restarting or returning to menu', async () => {
    state().place(2, 2);
    state().restart();
    await vi.advanceTimersByTimeAsync(500);
    expect(state().phase).toBe('playing');
    expect(state().game.history).toHaveLength(0);
    state().place(2, 2);
    state().menu();
    await vi.advanceTimersByTimeAsync(500);
    expect(state().phase).toBe('menu');
    expect(mocked.sound).not.toHaveBeenCalled();
  });

  it('rejects full columns without changing the turn', async () => {
    for (let i = 0; i < 5; i++) {
      state().place(2, 2);
      await vi.advanceTimersByTimeAsync(440);
    }
    const previous = state().game;
    state().place(2, 2);
    expect(state().phase).toBe('playing');
    expect(state().game).toBe(previous);
    expect(state().message).not.toBe('');
    expect(mocked.sound).toHaveBeenLastCalledWith('invalid');
  });

  it('announces victory only after the winning move settles', async () => {
    useGame.setState({ game: replay(winMoves, 6), phase: 'playing' });
    state().place(3, 0);
    expect(state().phase).toBe('animating');
    await vi.advanceTimersByTimeAsync(440);
    expect(state().phase).toBe('victory');
    expect(mocked.sound).toHaveBeenLastCalledWith('win');
    state().place(4, 4);
    expect(state().game.history).toHaveLength(7);
  });
});

describe('AI turn lifecycle', () => {
  it('waits for animation and thinking delay; locks human input through the AI turn', async () => {
    const pending = pendingBot();
    await beginBotTurn();
    expect(mocked.bot).toHaveBeenCalledTimes(1);
    expect(mocked.bot.mock.calls[0][0]).toBe(state().game);
    state().place(4, 4);
    pending.resolve({ x: 0, y: 0 });
    await vi.advanceTimersByTimeAsync(419);
    expect(state().game.history).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(state().phase).toBe('animating');
    expect(state().game.history).toHaveLength(2);
    state().place(4, 4);
    expect(state().game.history).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(440);
    expect(state().phase).toBe('playing');
    expect(state().game.currentPlayer).toBe(1);
  });

  it('cancels a thinking turn on pause and recomputes on resume', async () => {
    const old = pendingBot();
    await beginBotTurn();
    const signal = mocked.bot.mock.calls[0][2] as AbortSignal;
    await vi.advanceTimersByTimeAsync(420);
    state().pause();
    expect(signal.aborted).toBe(true);
    old.resolve({ x: 4, y: 4 });
    await vi.advanceTimersByTimeAsync(1000);
    expect(state().game.history).toHaveLength(1);
    expect(state().phase).toBe('paused');
    state().resume();
    expect(mocked.bot).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(420);
    expect(state().game.history[1]).toMatchObject({ x: 0, y: 0, player: 2 });
    await vi.advanceTimersByTimeAsync(440);
    expect(state().phase).toBe('playing');
  });

  it('resumes a human animation pause into an AI turn', async () => {
    state().start('ai');
    state().place(2, 2);
    state().pause();
    await vi.advanceTimersByTimeAsync(1000);
    expect(mocked.bot).not.toHaveBeenCalled();
    state().resume();
    expect(state().phase).toBe('ai-thinking');
    await vi.advanceTimersByTimeAsync(860);
    expect(state().game.history).toHaveLength(2);
    expect(state().phase).toBe('playing');
  });

  it.each(['restart', 'menu'] as const)('ignores a stale worker reply after %s', async (action) => {
    const old = pendingBot();
    await beginBotTurn();
    const signal = mocked.bot.mock.calls[0][2] as AbortSignal;
    await vi.advanceTimersByTimeAsync(420);
    state()[action]();
    const expectedGame = state().game;
    const expectedPhase = state().phase;
    expect(signal.aborted).toBe(true);
    old.resolve({ x: 4, y: 4 });
    await vi.advanceTimersByTimeAsync(1000);
    expect(state().game).toBe(expectedGame);
    expect(state().phase).toBe(expectedPhase);
  });

  it('rejects an old worker result even when a new game is also thinking', async () => {
    const old = pendingBot();
    await beginBotTurn();
    await vi.advanceTimersByTimeAsync(420);
    const current = pendingBot();
    await beginBotTurn();
    old.resolve({ x: 4, y: 4 });
    await vi.advanceTimersByTimeAsync(420);
    expect(state().game.history).toHaveLength(1);
    current.resolve({ x: 1, y: 1 });
    await vi.advanceTimersByTimeAsync(0);
    expect(state().game.history[1]).toMatchObject({ x: 1, y: 1 });
  });

  it('recovers from a worker failure and allows a retry', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    const pending = pendingBot();
    await beginBotTurn();
    pending.reject(new Error('Worker failed'));
    await vi.advanceTimersByTimeAsync(0);
    expect(state().phase).toBe('paused');
    expect(state().message).not.toBe('');
    expect(error).toHaveBeenCalledTimes(1);
    state().resume();
    await vi.advanceTimersByTimeAsync(860);
    expect(state().phase).toBe('playing');
    expect(state().game.history).toHaveLength(2);
  });

  it.each([null, { x: -1, y: 0 }])('recovers from an unusable worker reply %j', async (move) => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const pending = pendingBot();
    await beginBotTurn();
    pending.resolve(move);
    await vi.advanceTimersByTimeAsync(420);
    expect(state().phase).toBe('paused');
    expect(state().message).not.toBe('');
    expect(state().game.history).toHaveLength(1);
  });

  it('undoes both the AI response and the preceding human move', async () => {
    await beginBotTurn();
    await vi.advanceTimersByTimeAsync(860);
    state().undoMove();
    expect(state().game.history).toHaveLength(0);
    expect(state().game.currentPlayer).toBe(1);
    expect(state().phase).toBe('playing');
    expect(mocked.bot).toHaveBeenCalledTimes(1);
  });
});

describe('clock and replay', () => {
  it('counts active play and stops while paused, in menus or after victory', () => {
    state().tick();
    expect(state().elapsed).toBe(1);
    state().pause();
    state().tick();
    expect(state().elapsed).toBe(1);
    state().resume();
    state().place(2, 2);
    state().tick();
    expect(state().elapsed).toBe(2);
    state().menu();
    state().tick();
    expect(state().elapsed).toBe(2);
    state().start('local');
    expect(state().elapsed).toBe(0);
    useGame.setState({ game: replay(winMoves), phase: 'victory' });
    state().tick();
    expect(state().elapsed).toBe(0);
  });

  it('seeks through snapshots while preserving the original completed game', () => {
    const game = replay(winMoves);
    useGame.setState({ game, phase: 'victory' });
    state().openReplay();
    expect(displayedGame(state())).toEqual(game);
    state().seek(3);
    expect(displayedGame(state()).history).toHaveLength(3);
    expect(state().game).toBe(game);
    state().place(4, 4);
    state().tick();
    expect(state().game).toBe(game);
    expect(state().elapsed).toBe(0);
    state().seek(-5);
    expect(displayedGame(state()).history).toHaveLength(0);
    state().seek(100);
    expect(displayedGame(state())).toEqual(game);
    state().closeReplay();
    expect(state().phase).toBe('victory');
    expect(displayedGame(state())).toBe(game);
  });

  it('returns an unfinished replay to a resumable paused game', () => {
    state().place(2, 2);
    const game = state().game;
    state().openReplay();
    state().seek(0);
    expect(displayedGame(state()).history).toHaveLength(0);
    state().closeReplay();
    expect(state().phase).toBe('paused');
    expect(state().game).toBe(game);
    state().resume();
    expect(state().phase).toBe('playing');
  });

  it('normalizes fractional and non-finite replay positions safely', () => {
    useGame.setState({ game: replay(winMoves), phase: 'victory' });
    state().openReplay();
    state().seek(2.7);
    expect(displayedGame(state()).history).toHaveLength(2);
    state().seek(NaN);
    expect(() => displayedGame(state())).not.toThrow();
    state().seek(Infinity);
    expect(() => displayedGame(state())).not.toThrow();
  });
  it('resumes an interrupted bot turn exactly once, discarding its old calculation', async () => {
    useAccount.setState({ username: null });
    const old = pendingBot();
    await beginBotTurn();
    expect(readSavedGame()?.restored.currentPlayer).toBe(2);
    state().menu();
    state().resumeSavedGame();
    expect(state().phase).toBe('ai-thinking');
    old.resolve({ x: 4, y: 4 });
    await vi.advanceTimersByTimeAsync(1000);
    expect(state().game.history).toHaveLength(2);
    expect(state().game.history[1]).toMatchObject({ x: 0, y: 0 });
  });
  it('does not resume a save owned by another account', () => {
    useAccount.setState({ username: 'Alice' });
    state().start('local');
    state().place(2, 2);
    state().menu();
    useAccount.setState({ username: 'Bob' });
    state().resumeSavedGame();
    expect(state().phase).toBe('menu');
    useAccount.setState({ username: null });
  });
  it('discards a declined save without recreating it from menu actions', () => {
    useAccount.setState({ username: null });
    state().start('local');
    state().place(2, 2);
    const id = state().recordId;
    state().menu();
    state().discardSavedGame(id);
    expect(readSavedGame()).toBeNull();
    expect(state().hasSavedGame).toBe(false);
    state().view('top');
    expect(readSavedGame()).toBeNull();
    state().resumeSavedGame();
    expect(state().phase).toBe('menu');
  });
  it('does not discard an active, replaced or other account save', () => {
    useAccount.setState({ username: 'Alice' });
    state().start('local');
    const id = state().recordId;
    state().discardSavedGame(id);
    expect(readSavedGame()?.recordId).toBe(id);
    state().menu();
    state().discardSavedGame('older-record');
    expect(readSavedGame()?.recordId).toBe(id);
    useAccount.setState({ username: 'Bob' });
    state().discardSavedGame(id);
    expect(readSavedGame()?.recordId).toBe(id);
    useAccount.setState({ username: null });
  });
});
