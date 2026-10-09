import { describe, expect, it } from 'vitest';
import { dailyDate, dailyExpiresAt, isDailyChallenge } from './daily';

const preset = [
  { x: 0, y: 0 },
  { x: 0, y: 1 },
  { x: 1, y: 0 },
  { x: 1, y: 1 },
  { x: 2, y: 0 },
  { x: 4, y: 4 },
  { x: 2, y: 2 },
  { x: 4, y: 3 },
  { x: 1, y: 2 },
  { x: 3, y: 4 },
  { x: 0, y: 2 },
  { x: 3, y: 3 },
];

describe('daily challenge contract', () => {
  it('changes the date at Moscow midnight and gives all time zones one deadline', () => {
    expect(dailyDate(Date.parse('2026-10-09T20:59:59.999Z'))).toBe('2026-10-09');
    expect(dailyDate(Date.parse('2026-10-09T21:00:00.000Z'))).toBe('2026-10-10');
    expect(dailyExpiresAt('2026-10-09')).toBe(Date.parse('2026-10-09T21:00:00Z'));
    expect(dailyDate(Date.parse('2026-12-31T21:00:00Z'))).toBe('2027-01-01');
    expect(dailyExpiresAt('2028-02-29')).toBe(Date.parse('2028-02-29T21:00:00Z'));
  });

  it('rejects impossible or loosely formatted dates', () => {
    for (const date of ['2026-02-29', '2026-04-31', '2026-13-01', '26-10-09', '2026-1-01'])
      expect(() => dailyExpiresAt(date)).toThrow('Invalid daily challenge date');
  });

  it('rejects altered or illegal cached challenges', () => {
    const challenge = {
      id: 'daily-1-2026-10-09',
      date: '2026-10-09',
      version: 1,
      preset,
      expiresAt: dailyExpiresAt('2026-10-09'),
    };
    expect(isDailyChallenge(challenge)).toBe(true);
    expect(isDailyChallenge(null)).toBe(false);
    expect(isDailyChallenge({ ...challenge, id: 'other-day' })).toBe(false);
    expect(isDailyChallenge({ ...challenge, version: 2 })).toBe(false);
    expect(isDailyChallenge({ ...challenge, expiresAt: challenge.expiresAt + 1 })).toBe(false);
    expect(isDailyChallenge({ ...challenge, preset: preset.slice(1) })).toBe(false);
    expect(isDailyChallenge({ ...challenge, preset: preset.map(() => ({ x: 0, y: 0 })) })).toBe(
      false,
    );
    expect(
      isDailyChallenge({ ...challenge, preset: [...preset.slice(0, 11), { x: 5, y: 0 }] }),
    ).toBe(false);
    expect(
      isDailyChallenge({ ...challenge, preset: [...preset, { x: 3, y: 0 }, { x: 2, y: 4 }] }),
    ).toBe(false);
  });
});
