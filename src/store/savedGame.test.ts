// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest';
import { replay } from '../game/core';
import { levelPosition, getLevel } from '../game/levels';
import { readSavedGame, removeSavedGame, writeSavedGame } from './savedGame';

const data = () => ({
  mode: 'ai' as const,
  game: replay([{ x: 2, y: 2 }]),
  difficulty: 'medium' as const,
  names: ['Alice', 'FOUR AI'] as [string, string],
  elapsed: 23,
  recordId: 'local-one',
  accountAtStart: 'Alice',
  levelId: null,
  levelBestBefore: null,
  xray: false,
  layers: [1, 3],
  cameraView: 'top' as const,
});
beforeEach(() => localStorage.clear());
describe('unfinished offline games', () => {
  it('replays saved moves and preserves the bot turn and view', () => {
    writeSavedGame(data());
    const saved = readSavedGame()!;
    expect(saved.restored.currentPlayer).toBe(2);
    expect(saved.restored).toEqual(data().game);
    expect(saved.layers).toEqual([1, 3]);
    expect(saved.elapsed).toBe(23);
  });
  it('restores a level only when its preset matches', () => {
    writeSavedGame({ ...data(), mode: 'level', levelId: 1, game: levelPosition(getLevel(1)!) });
    expect(readSavedGame()?.levelId).toBe(1);
    writeSavedGame({ ...data(), mode: 'level', levelId: 1 });
    expect(readSavedGame()).toBeNull();
  });
  it('rejects corrupted, finished and unsupported saves', () => {
    localStorage.setItem('four-cubed-active-game-v1', '{bad');
    expect(readSavedGame()).toBeNull();
    writeSavedGame({
      ...data(),
      game: replay([
        { x: 0, y: 0 },
        { x: 0, y: 4 },
        { x: 1, y: 0 },
        { x: 1, y: 4 },
        { x: 2, y: 0 },
        { x: 2, y: 4 },
        { x: 3, y: 0 },
      ]),
    });
    expect(readSavedGame()).toBeNull();
    writeSavedGame(data());
    const value = JSON.parse(localStorage.getItem('four-cubed-active-game-v1')!);
    value.mode = 'online';
    localStorage.setItem('four-cubed-active-game-v1', JSON.stringify(value));
    expect(readSavedGame()).toBeNull();
  });
  it('does not delete a different unfinished game', () => {
    writeSavedGame(data());
    removeSavedGame('another-game');
    expect(readSavedGame()).not.toBeNull();
    removeSavedGame('local-one');
    expect(readSavedGame()).toBeNull();
  });
});
