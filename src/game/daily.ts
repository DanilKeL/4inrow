import { replay, type GameState } from './core';

export interface DailyPoint {
  x: number;
  y: number;
}

export interface DailyChallenge {
  id: string;
  date: string;
  version: 1;
  preset: DailyPoint[];
  expiresAt: number;
}

export interface DailyStanding {
  rank: number;
  username: string;
  moves: number;
  completedAt: number;
}

export interface DailyResponse {
  username: string | null;
  challenge: DailyChallenge;
  leaderboard: DailyStanding[];
  ownBest: number | null;
  now: number;
  rank?: number;
}

// This policy is part of challenge version 1. Randomness and clock deadlines are forbidden.
export const DAILY_BOT_DIFFICULTY = 'medium' as const;
export const DAILY_BOT_OPTIONS = { deterministic: true, nodeBudget: 6000 } as const;
const MOSCOW_OFFSET = 3 * 60 * 60 * 1000;
const DAY = 24 * 60 * 60 * 1000;

/** A challenge changes at midnight in Moscow, independently of the player's time zone. */
export function dailyDate(now: number = Date.now()): string {
  return new Date(now + MOSCOW_OFFSET).toISOString().slice(0, 10);
}

export function dailyExpiresAt(date: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('Invalid daily challenge date');
  const midnight = Date.parse(`${date}T00:00:00.000Z`);
  if (!Number.isFinite(midnight) || new Date(midnight).toISOString().slice(0, 10) !== date)
    throw new Error('Invalid daily challenge date');
  return midnight + DAY - MOSCOW_OFFSET;
}

export function dailyPosition(challenge: DailyChallenge): GameState {
  return replay(challenge.preset);
}

export function dailyMoveCount(game: GameState, challenge: DailyChallenge): number {
  return game.history.slice(challenge.preset.length).filter((move) => move.player === 1).length;
}

/** Validate untrusted cached/public data before restoring its position. */
export function isDailyChallenge(value: unknown): value is DailyChallenge {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const data = value as Record<string, unknown>;
  if (
    data.version !== 1 ||
    typeof data.date !== 'string' ||
    data.id !== `daily-1-${data.date}` ||
    !Array.isArray(data.preset) ||
    data.preset.length < 12 ||
    data.preset.length > 100 ||
    data.preset.length % 2 !== 0
  )
    return false;
  for (const point of data.preset) {
    if (!point || typeof point !== 'object' || Array.isArray(point)) return false;
    if (
      !Number.isInteger(point.x) ||
      !Number.isInteger(point.y) ||
      point.x < 0 ||
      point.x > 4 ||
      point.y < 0 ||
      point.y > 4
    )
      return false;
  }
  try {
    if (data.expiresAt !== dailyExpiresAt(data.date)) return false;
    const position = replay(data.preset);
    return position.status === 'playing' && position.currentPlayer === 1;
  } catch {
    return false;
  }
}
