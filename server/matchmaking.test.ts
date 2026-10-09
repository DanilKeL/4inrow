import { describe, expect, it } from 'vitest';
import { ratingSearchRange, waitingPairs, type MatchCandidate } from './matchmaking';

const player = (id: string, rating: number | null, queuedAt = 0): MatchCandidate<string> => ({
  id,
  rating,
  queuedAt,
  order: 0,
  account: rating === null ? null : id,
});

describe('progressive Elo matchmaking', () => {
  it('preserves original queue priority when reconnects reorder equally timed searches', () => {
    const candidates = [
      { ...player('b', 1400), order: 1 },
      { ...player('c', 1800), order: 2 },
      { ...player('a', 1000), order: 0 },
    ];
    expect(waitingPairs(candidates, 9000, 10)).toEqual([['a', 'b']]);
  });
  it('starts at 100 Elo, widens every 3 seconds and removes the limit at 30 seconds', () => {
    for (const [wait, range] of [
      [-1, 100],
      [0, 100],
      [2999, 100],
      [3000, 200],
      [6000, 300],
      [29999, 1000],
      [30000, Infinity],
    ])
      expect(ratingSearchRange(wait)).toBe(range);
  });
  it('matches nearby players immediately without waiting for the first expansion', () => {
    expect(waitingPairs([player('a', 1000), player('b', 1100)], 0, 10)).toEqual([['a', 'b']]);
    expect(waitingPairs([player('a', 1000), player('b', 1101)], 0, 10)).toEqual([]);
  });
  it('chooses the closest eligible player, respecting the oldest search first', () => {
    expect(
      waitingPairs([player('a', 1000), player('b', 1050, 1), player('c', 1010, 2)], 100, 10),
    ).toEqual([['a', 'c']]);
  });
  it('requires the rating gap to fit both players, protecting new arrivals', () => {
    expect(waitingPairs([player('a', 1000), player('b', 1500, 29000)], 30000, 10)).toEqual([]);
    expect(waitingPairs([player('a', 1000), player('b', 1500, 29000)], 41000, 10)).toEqual([
      ['a', 'b'],
    ]);
  });
  it('widens without requiring a new player to arrive and eventually matches extreme ratings', () => {
    const candidates = [player('a', 1000), player('b', 1400)];
    expect(waitingPairs(candidates, 8999, 10)).toEqual([]);
    expect(waitingPairs(candidates, 9000, 10)).toEqual([['a', 'b']]);
    expect(waitingPairs([player('a', 0), player('b', 1000000)], 29999, 10)).toEqual([]);
    expect(waitingPairs([player('a', 0), player('b', 1000000)], 30000, 10)).toEqual([['a', 'b']]);
  });
  it('keeps guests separate and matches them immediately', () => {
    expect(waitingPairs([player('a', 1000), player('b', null), player('c', null)], 0, 10)).toEqual([
      ['b', 'c'],
    ]);
  });
  it('never pairs the same account or places one player in multiple matches', () => {
    const candidates = [
      player('a', 1000),
      { ...player('copy', 1000), account: 'a' },
      player('b', 1000),
      player('c', 1000),
    ];
    const pairs = waitingPairs(candidates, 0, 10);
    expect(pairs).toEqual([
      ['a', 'b'],
      ['copy', 'c'],
    ]);
    expect(new Set(pairs.flat()).size).toBe(pairs.flat().length);
  });
  it('preserves first-in priority on equal distance and respects available room capacity', () => {
    const candidates = [
      player('new', 900, 20),
      player('old', 1000),
      player('earlier', 1100, 10),
      player('other', 1150, 30),
    ];
    expect(waitingPairs(candidates, 100, 1)).toEqual([['old', 'earlier']]);
    expect(waitingPairs(candidates, 100, 0)).toEqual([]);
    expect(waitingPairs(candidates, 100, 1)).toHaveLength(1);
    expect(candidates[0].id).toBe('new');
  });
});
