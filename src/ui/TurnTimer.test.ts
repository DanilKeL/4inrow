import { describe, expect, it } from 'vitest';
import { remainingTurnSeconds } from './turnTime';

describe('online turn timer', () => {
  it('rounds the server deadline up to a whole visible second', () => {
    expect(remainingTurnSeconds(10_001, undefined, 9_000)).toBe(2);
    expect(remainingTurnSeconds(10_000, undefined, 9_000)).toBe(1);
    expect(remainingTurnSeconds(9_000, undefined, 10_000)).toBe(0);
  });

  it('shows no numeric limit when the server did not create a deadline', () => {
    expect(remainingTurnSeconds(undefined, undefined, 10_000)).toBeNull();
  });

  it('freezes at the remaining turn time while an agreed pause is active', () => {
    expect(remainingTurnSeconds(150_000, 120_000, 70_000)).toBe(30);
    expect(remainingTurnSeconds(150_000, 120_000, 110_000)).toBe(30);
  });
});
