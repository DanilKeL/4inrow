import { deserialize, serialize, type GameState } from '../game/core';
import { getLevel } from '../game/levels';
import type { Difficulty } from '../game/ai';

const KEY = 'four-cubed-active-game-v1';
export interface SavedGame {
  version: 1;
  mode: 'local' | 'ai' | 'level';
  game: string;
  difficulty: Difficulty;
  names: [string, string];
  elapsed: number;
  recordId: string;
  accountAtStart: string | null;
  levelId: number | null;
  levelBestBefore: number | null;
  xray: boolean;
  layers: number[];
  cameraView: 'perspective' | 'top' | 'front';
}
export function readSavedGame(): (SavedGame & { restored: GameState }) | null {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) ?? 'null') as SavedGame | null;
    if (
      !saved ||
      saved.version !== 1 ||
      !['local', 'ai', 'level'].includes(saved.mode) ||
      !['easy', 'medium', 'hard'].includes(saved.difficulty) ||
      !Array.isArray(saved.names) ||
      saved.names.length !== 2 ||
      saved.names.some((name) => typeof name !== 'string' || name.length > 100) ||
      typeof saved.recordId !== 'string' ||
      !saved.recordId ||
      saved.recordId.length > 160 ||
      (saved.accountAtStart !== null &&
        (typeof saved.accountAtStart !== 'string' || saved.accountAtStart.length > 24)) ||
      !Number.isFinite(saved.elapsed) ||
      saved.elapsed < 0 ||
      saved.elapsed > 365 * 86400 ||
      (saved.levelBestBefore !== null &&
        (!Number.isInteger(saved.levelBestBefore) ||
          saved.levelBestBefore <= 0 ||
          saved.levelBestBefore > 63)) ||
      !Array.isArray(saved.layers) ||
      saved.layers.some((z) => !Number.isInteger(z) || z < 0 || z > 4) ||
      !['perspective', 'top', 'front'].includes(saved.cameraView) ||
      typeof saved.xray !== 'boolean'
    )
      return null;
    const restored = deserialize(saved.game);
    if (restored.status !== 'playing') return null;
    if (saved.mode === 'level') {
      const level = getLevel(saved.levelId);
      if (
        !level ||
        restored.history.length < level.preset.length ||
        level.preset.some(
          (move, i) => move.x !== restored.history[i].x || move.y !== restored.history[i].y,
        )
      )
        return null;
    } else if (saved.levelId !== null) return null;
    return { ...saved, restored };
  } catch {
    return null;
  }
}
export function writeSavedGame(saved: Omit<SavedGame, 'version' | 'game'> & { game: GameState }) {
  try {
    localStorage.setItem(
      KEY,
      JSON.stringify({ ...saved, version: 1, game: serialize(saved.game) }),
    );
  } catch {
    /* Storage can be disabled or full. Current play is unaffected. */
  }
}
export function removeSavedGame(recordId: string) {
  try {
    if (readSavedGame()?.recordId === recordId) localStorage.removeItem(KEY);
  } catch {
    /* Storage is optional. */
  }
}
