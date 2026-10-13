// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createGame, replay } from '../game/core';
import type { OnlineHandlers } from '../network/client';
import type { LobbySnapshot } from '../network/protocol';
import { WIN_CAMERA_MS, WIN_FALL_MS } from '../game/victoryPresentation';

const mocked = vi.hoisted(() => ({
  sound: vi.fn(),
  handlers: null as OnlineHandlers | null,
  settings: { sound: true, animations: true, xrayDefault: false },
}));
vi.mock('../audio/sound', () => ({ playSound: mocked.sound }));
vi.mock('./settingsStore', () => ({ useSettings: { getState: () => mocked.settings } }));
vi.mock('./accountStore', () => ({
  currentPlayerName: () => 'One',
  secondGuestName: () => 'Two',
  useAccount: {
    getState: () => ({ username: null, load: () => Promise.resolve() }),
    subscribe: () => () => {},
  },
}));
vi.mock('../network/client', () => ({
  onlineClient: {
    connect: (_command: unknown, handlers: OnlineHandlers) => {
      mocked.handlers = handlers;
    },
    leave: vi.fn(),
    disconnect: vi.fn(),
    send: vi.fn(),
  },
}));
import { useGame } from './gameStore';

const moves = [
  { x: 0, y: 0 },
  { x: 0, y: 4 },
  { x: 1, y: 0 },
  { x: 1, y: 4 },
  { x: 2, y: 0 },
  { x: 2, y: 4 },
  { x: 3, y: 0 },
];
const snapshot = (won = false): LobbySnapshot => ({
  code: 'ABCDE',
  kind: 'quick',
  game: replay(moves.slice(0, won ? 7 : 6)),
  players: [
    { name: 'One', connected: true },
    { name: 'Two', connected: true },
  ],
  revision: won ? 8 : 7,
  round: 1,
  startedAt: Date.now() - 10000,
  finishedAt: won ? Date.now() : null,
  rematch: [],
  ranking: {
    rated: true,
    points: [1000, 1000],
    ...(won ? { changes: [16, -16] as [number, number] } : {}),
  },
});
async function connect() {
  useGame.getState().createOnline('One');
  await Promise.resolve();
  mocked.handlers!.onStatus('connected');
  mocked.handlers!.onEvent({
    type: 'session',
    code: 'ABCDE',
    token: 'test',
    player: 1,
    snapshot: snapshot(),
  });
}
beforeEach(async () => {
  vi.useFakeTimers();
  mocked.sound.mockReset();
  mocked.settings.animations = true;
  mocked.settings.sound = true;
  await connect();
});
afterEach(() => {
  useGame.getState().menu();
  vi.useRealTimers();
});

describe('ranked victory landing', () => {
  it.each([true, false])(
    'plays the victory sound at landing in rated=%s online, including repeated broadcasts',
    (rated) => {
      const won = { ...snapshot(true), ranking: { ...snapshot(true).ranking!, rated } };
      mocked.handlers!.onEvent({ type: 'state', snapshot: won });
      vi.advanceTimersByTime(440);
      expect(mocked.sound).not.toHaveBeenCalled();
      mocked.handlers!.onEvent({ type: 'state', snapshot: { ...won, revision: 9, rematch: [2] } });
      expect(useGame.getState().phase).toBe('animating');
      vi.advanceTimersByTime(WIN_CAMERA_MS + WIN_FALL_MS - 441);
      expect(mocked.sound).not.toHaveBeenCalled();
      vi.advanceTimersByTime(1);
      expect(mocked.sound).toHaveBeenCalledExactlyOnceWith('win');
      expect(useGame.getState().phase).toBe('victory');
      mocked.handlers!.onEvent({ type: 'state', snapshot: { ...won, revision: 10, rematch: [2] } });
      vi.advanceTimersByTime(2000);
      expect(mocked.sound).toHaveBeenCalledTimes(1);
    },
  );

  it('cancels the preceding victory when a new round starts', () => {
    mocked.handlers!.onEvent({ type: 'state', snapshot: snapshot(true) });
    vi.advanceTimersByTime(300);
    mocked.handlers!.onEvent({
      type: 'state',
      snapshot: {
        ...snapshot(),
        game: createGame(),
        revision: 9,
        round: 2,
        ranking: { rated: false, points: [1016, 984] },
      },
    });
    vi.advanceTimersByTime(2000);
    expect(mocked.sound).not.toHaveBeenCalled();
    expect(useGame.getState().phase).toBe('playing');
  });

  it('keeps the short settlement when animations are disabled', () => {
    mocked.settings.animations = false;
    mocked.handlers!.onEvent({ type: 'state', snapshot: snapshot(true) });
    vi.advanceTimersByTime(79);
    expect(mocked.sound).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(mocked.sound).toHaveBeenCalledExactlyOnceWith('win');
    expect(useGame.getState().phase).toBe('victory');
  });
});
