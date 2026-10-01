import { expect, it } from 'vitest';
import { ratingDelta } from './rating';
it('awards strength-adjusted, zero-sum Elo with sensible extreme gaps', () => {
  expect(ratingDelta(1000, 1000, 1)).toBe(16);
  expect(ratingDelta(1000, 1200, 1)).toBe(24);
  expect(ratingDelta(1200, 1000, 1)).toBe(8);
  expect(ratingDelta(1000, 1400, 1)).toBe(29);
  expect(ratingDelta(1400, 1000, 1)).toBe(3);
  expect(ratingDelta(1000, 1000, 0.5)).toBe(0);
  expect(ratingDelta(1000, 1400, 0.5)).toBe(13);
  expect(ratingDelta(1400, 1000, 0.5)).toBe(-13);
  expect(ratingDelta(3000, 1000, 1)).toBe(1);
  expect(ratingDelta(1000, 3000, 0)).toBe(-1);
  expect(ratingDelta(0, 1000, 0)).toBe(0);
  expect(ratingDelta(1000, 0, 1)).toBe(0);
});
