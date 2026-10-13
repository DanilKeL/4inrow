import type { GameState } from './core';

export const WIN_FALL_MS = 1150;
export const WIN_LINE_MS = 700;
export const RESULT_DELAY_MS = 3600;
export const REDUCED_RESULT_DELAY_MS = 1600;

export function hasWinningLine(game: GameState, endReason?: string): boolean {
  return Boolean(game.status === 'won' && game.winningLines.length && !endReason);
}

export function resultDelay(game: GameState, animations: boolean, endReason?: string): number {
  if (hasWinningLine(game, endReason))
    return animations ? RESULT_DELAY_MS : REDUCED_RESULT_DELAY_MS;
  return game.status === 'draw' ? 1100 : 600;
}

export function moveAnimationDelay(
  game: GameState,
  animations: boolean,
  reducedMotion: boolean,
  endReason?: string,
): number {
  if (!animations) return 80;
  return hasWinningLine(game, endReason) && !reducedMotion ? WIN_FALL_MS : 440;
}
