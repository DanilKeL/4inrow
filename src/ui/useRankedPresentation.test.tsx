// @vitest-environment jsdom
import { act, cleanup, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useAnimatedInteger, useResultReveal } from './useRankedPresentation';
import { resultDelay } from '../game/victoryPresentation';
import { replay } from '../game/core';
import type { LobbySnapshot } from '../network/protocol';

beforeEach(() => {
  vi.useFakeTimers({
    toFake: [
      'setTimeout',
      'clearTimeout',
      'performance',
      'requestAnimationFrame',
      'cancelAnimationFrame',
    ],
  });
  vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('ranked result timing', () => {
  it('holds the board for the full sequence and does not restart for round updates', () => {
    const { result, rerender } = renderHook(({ key, ready }) => useResultReveal(key, 3600, ready), {
      initialProps: { key: 'ABCDE-1', ready: true },
    });
    act(() => vi.advanceTimersByTime(2000));
    rerender({ key: 'ABCDE-1', ready: true });
    act(() => vi.advanceTimersByTime(1599));
    expect(result.current).toBe(false);
    act(() => vi.advanceTimersByTime(1));
    expect(result.current).toBe(true);
    rerender({ key: 'ABCDE-2', ready: true });
    expect(result.current).toBe(false);
    act(() => vi.advanceTimersByTime(3600));
    expect(result.current).toBe(true);
  });

  it('waits for assets and cancels pending reveals when leaving the match', () => {
    const { result, rerender, unmount } = renderHook(
      ({ key, ready }: { key: string | null; ready: boolean }) => useResultReveal(key, 3600, ready),
      { initialProps: { key: 'ABCDE-1' as string | null, ready: false } },
    );
    act(() => vi.advanceTimersByTime(10000));
    expect(result.current).toBe(false);
    rerender({ key: 'ABCDE-1', ready: true });
    act(() => vi.advanceTimersByTime(2000));
    rerender({ key: null, ready: true });
    act(() => vi.advanceTimersByTime(4000));
    expect(result.current).toBe(false);
    unmount();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('counts only time with the game visible so returning users can inspect the board', () => {
    const visibility = vi.spyOn(document, 'visibilityState', 'get');
    const { result } = renderHook(() => useResultReveal('ABCDE-1', 3600, true));
    act(() => vi.advanceTimersByTime(1200));
    act(() => {
      visibility.mockReturnValue('hidden');
      document.dispatchEvent(new Event('visibilitychange'));
      vi.advanceTimersByTime(30000);
    });
    expect(result.current).toBe(false);
    act(() => {
      visibility.mockReturnValue('visible');
      document.dispatchEvent(new Event('visibilitychange'));
      vi.advanceTimersByTime(2399);
    });
    expect(result.current).toBe(false);
    act(() => vi.advanceTimersByTime(1));
    expect(result.current).toBe(true);
  });

  it('uses a shorter static hold for reduced motion and skips cinematics for forfeits', () => {
    const game = replay([
      { x: 0, y: 0 },
      { x: 0, y: 4 },
      { x: 1, y: 0 },
      { x: 1, y: 4 },
      { x: 2, y: 0 },
      { x: 2, y: 4 },
      { x: 3, y: 0 },
    ]);
    const snapshot = { game, ranking: { rated: true } } as LobbySnapshot;
    expect(resultDelay(snapshot.game, true)).toBe(3600);
    expect(resultDelay(snapshot.game, false)).toBe(1600);
    expect(resultDelay(snapshot.game, true, 'Соперник сдался')).toBe(600);
    expect(resultDelay({ ...game, status: 'draw' }, true)).toBe(1100);
  });
});

describe('Elo animation', () => {
  it('starts from the previous rating when the banner appears, not during the board animation', () => {
    const { result, rerender } = renderHook(
      ({ enabled }) => useAnimatedInteger(1016, 1000, enabled, false, 80),
      {
        initialProps: { enabled: false },
      },
    );
    act(() => vi.advanceTimersByTime(3600));
    expect(result.current).toBe(1000);
    rerender({ enabled: true });
    expect(result.current).toBe(1000);
    act(() => vi.advanceTimersByTime(500));
    expect(result.current).toBeGreaterThan(1000);
    expect(result.current).toBeLessThan(1016);
    act(() => vi.advanceTimersByTime(600));
    expect(result.current).toBe(1016);
  });

  it('animates lost points and cancels frames on unmount', () => {
    const { result, unmount } = renderHook(() => useAnimatedInteger(-16, 0, true, false, 220));
    expect(result.current).toBe(0);
    act(() => vi.advanceTimersByTime(600));
    expect(result.current).toBeLessThan(0);
    expect(result.current).toBeGreaterThan(-16);
    unmount();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('shows the exact total immediately when animations are disabled', () => {
    const { result } = renderHook(() => useAnimatedInteger(984, 1000, true, true, 80));
    expect(result.current).toBe(984);
    expect(vi.getTimerCount()).toBe(0);
  });
});
