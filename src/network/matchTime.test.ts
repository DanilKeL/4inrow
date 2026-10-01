import { expect, it } from 'vitest';
import { onlineElapsed } from './matchTime';

it('excludes active and completed pauses from game time', () => {
  const match = {
    startedAt: 1000,
    finishedAt: null,
    pause: { used: true, totalMs: 0, startedAt: 11000, endsAt: 131000 },
  };
  expect(onlineElapsed(match, 11000)).toBe(10);
  expect(onlineElapsed(match, 90000)).toBe(10);
  expect(onlineElapsed(match, 132000)).toBe(11);
  expect(
    onlineElapsed({ ...match, finishedAt: 135000, pause: { used: true, totalMs: 120000 } }),
  ).toBe(14);
  expect(onlineElapsed({ startedAt: null, finishedAt: null })).toBe(0);
});
