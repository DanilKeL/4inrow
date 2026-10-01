import { replay, type GameState } from '../core';
import data from './levels.json';

export interface Level {
  id: number;
  chapter: string;
  preset: Array<{ x: number; y: number }>;
}
export const LEVELS: readonly Level[] = data;
// Versioned together with the positions: do not change this policy without resetting records.
export const LEVEL_BOT_OPTIONS = { deterministic: true, nodeBudget: 6000 } as const;
export const getLevel = (id: number | null) => LEVELS.find((level) => level.id === id);
export const levelPosition = (level: Level) => replay(level.preset);
export function levelMoveCount(game: GameState, level: Level): number {
  return game.history.slice(level.preset.length).filter((move) => move.player === 1).length;
}
export function moveLabel(count: number): string {
  const ending =
    count % 100 >= 11 && count % 100 <= 14
      ? 'ходов'
      : count % 10 === 1
        ? 'ход'
        : count % 10 >= 2 && count % 10 <= 4
          ? 'хода'
          : 'ходов';
  return `${count} ${ending}`;
}
