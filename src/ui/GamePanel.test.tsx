// @vitest-environment jsdom
import { act, cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createGame, replay } from '../game/core';
import type { GameState } from '../game/core';
import { GamePanel } from './GamePanel';
import type { DailyChallenge } from '../game/daily';

const mocked = vi.hoisted(() => ({
  animations: true,
  reduced: false,
  state: {
    game: null as unknown as GameState,
    phase: 'playing',
    mode: 'local',
    recordId: 'game-1',
    levelId: null as number | null,
    levelBestBefore: null,
    dailyChallenge: null as DailyChallenge | null,
    online: null,
    names: ['One', 'Two'],
    elapsed: 30,
    restart: vi.fn(),
    openReplay: vi.fn(),
  },
}));
vi.mock('../store/gameStore', () => ({ useGame: () => mocked.state }));
vi.mock('../store/settingsStore', () => ({
  useSettings: (selector: (s: unknown) => unknown) => selector({ animations: mocked.animations }),
}));
vi.mock('../store/levelStore', () => ({
  useLevelProgress: (selector: (s: unknown) => unknown) => selector({ best: {} }),
}));
vi.mock('../store/dailyStore', () => ({ useDaily: () => ({ result: null, pending: [] }) }));
vi.mock('motion/react', () => ({ useReducedMotion: () => mocked.reduced }));
const won = () =>
  replay([
    { x: 0, y: 0 },
    { x: 0, y: 4 },
    { x: 1, y: 0 },
    { x: 1, y: 4 },
    { x: 2, y: 0 },
    { x: 2, y: 4 },
    { x: 3, y: 0 },
  ]);
const props = { onMenu: vi.fn(), onLevels: vi.fn(), onDailyResults: vi.fn() };

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'performance'] });
  vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
  mocked.state.game = createGame();
  mocked.state.phase = 'playing';
  mocked.state.mode = 'local';
  mocked.state.recordId = 'game-1';
  mocked.state.levelId = null;
  mocked.state.dailyChallenge = null;
  mocked.animations = true;
  mocked.reduced = false;
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('inline completion', () => {
  it.each(['local', 'ai', 'level', 'daily'])(
    'lets the winning board remain visible in %s without opening a dialog',
    (mode) => {
      mocked.state.mode = mode;
      mocked.state.game = won();
      mocked.state.phase = 'animating';
      if (mode === 'level') mocked.state.levelId = 9;
      if (mode === 'daily')
        mocked.state.dailyChallenge = {
          id: 'daily-1-2026-10-13',
          date: '2026-10-13',
          version: 1,
          preset: [],
          expiresAt: Date.now() + 10000,
        };
      render(<GamePanel {...props} />);
      expect(
        screen.queryByRole('button', { name: /Ещё партия|Повторить уровень|Повторить задачу/ }),
      ).toBeNull();
      act(() => vi.advanceTimersByTime(3599));
      expect(
        screen.queryByRole('button', { name: /Ещё партия|Повторить уровень|Повторить задачу/ }),
      ).toBeNull();
      act(() => vi.advanceTimersByTime(1));
      expect(
        screen.getByRole('button', { name: /Ещё партия|Повторить уровень|Повторить задачу/ }),
      ).toBeTruthy();
      expect(screen.queryByRole('dialog')).toBeNull();
    },
  );

  it('does not delay ordinary controls during play or replay and resets for another game', () => {
    const { rerender } = render(<GamePanel {...props} />);
    expect(screen.getByRole('heading', { name: 'Текущая партия' })).toBeTruthy();
    mocked.state.game = won();
    rerender(<GamePanel {...props} />);
    act(() => vi.advanceTimersByTime(3600));
    expect(screen.getByRole('heading', { name: 'Победа: One' })).toBeTruthy();
    mocked.state.phase = 'replay';
    rerender(<GamePanel {...props} />);
    expect(screen.getByRole('heading', { name: 'Повтор партии' })).toBeTruthy();
    mocked.state.phase = 'victory';
    rerender(<GamePanel {...props} />);
    expect(screen.getByRole('heading', { name: 'Победа: One' })).toBeTruthy();
    mocked.state.recordId = 'game-2';
    rerender(<GamePanel {...props} />);
    expect(screen.queryByRole('heading', { name: 'Победа: One' })).toBeNull();
  });

  it.each([false, true])(
    'uses a static hold when animations are disabled or reduced motion is requested (%s)',
    (reduced) => {
      mocked.animations = reduced;
      mocked.reduced = reduced;
      mocked.state.game = won();
      render(<GamePanel {...props} />);
      act(() => vi.advanceTimersByTime(1599));
      expect(screen.queryByRole('heading', { name: 'Победа: One' })).toBeNull();
      act(() => vi.advanceTimersByTime(1));
      expect(screen.getByRole('heading', { name: 'Победа: One' })).toBeTruthy();
    },
  );
});
