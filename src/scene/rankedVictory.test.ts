import { describe, expect, it } from 'vitest';
import { WIN_FALL_MS, WIN_LINE_MS } from '../game/victoryPresentation';
import { visibleLineSegments } from './layers';
import { rankedSegmentProgress, rankedVictoryProgress } from './rankedVictory';

describe('ranked victory reveal', () => {
  it('keeps winning lines, rings and dimming hidden until the last chip lands', () => {
    const initial = rankedVictoryProgress(0);
    const falling = rankedVictoryProgress(WIN_FALL_MS / 2);
    expect(initial.fallOffset).toBeCloseTo(2.2);
    expect(falling.fallOffset).toBeGreaterThan(0);
    expect(falling.lineProgress).toBe(0);
    expect(falling.ringProgress).toBe(0);
    expect(falling.dimProgress).toBe(0);
    expect(rankedVictoryProgress(WIN_FALL_MS).fallOffset).toBe(0);
  });

  it('reveals the line continuously while other chips fade, then holds the result', () => {
    const halfway = rankedVictoryProgress(WIN_FALL_MS + WIN_LINE_MS / 2);
    expect(halfway.lineProgress).toBeCloseTo(0.5);
    expect(halfway.dimProgress).toBeCloseTo(0.5);
    expect(halfway.ringProgress).toBe(1);
    const finished = rankedVictoryProgress(WIN_FALL_MS + WIN_LINE_MS);
    expect(finished).toEqual({ fallOffset: 0, lineProgress: 1, dimProgress: 1, ringProgress: 1 });
    expect(rankedVictoryProgress(10000)).toEqual(finished);
  });

  it('draws adjacent segments in sequence and never links across a hidden layer', () => {
    expect([0, 1, 2].map((segment) => rankedSegmentProgress(0.5, segment, 3))).toEqual([1, 0.5, 0]);
    expect(rankedSegmentProgress(0, 0, 3)).toBe(0);
    expect(rankedSegmentProgress(1, 2, 3)).toBe(1);
    const vertical = [0, 1, 2, 3].map((z) => ({ x: 0, y: 0, z }));
    const segments = visibleLineSegments(vertical, [0, 2, 3]);
    expect(segments).toEqual([[vertical[2], vertical[3]]]);
    // Filtering layers does not skip directly from the first to the last chip.
    expect(rankedSegmentProgress(0.5, vertical.indexOf(segments[0][0]), 3)).toBe(0);
  });
});
