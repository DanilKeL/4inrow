import { expect, it } from 'vitest';
import { replay } from '../game/core';
import { tutorialExamples } from './tutorialExamples';

it('shows legal alternating games with supported pieces and the advertised winning direction', () => {
  const directions = [
    [1, 0, 0],
    [0, 0, 1],
    [1, 1, 0],
    [1, 1, 0],
    [1, 1, 1],
  ];
  expect(tutorialExamples).toHaveLength(6);
  for (const [i, example] of tutorialExamples.entries()) {
    const moves = example.moves.map(([x, y]) => ({ x, y }));
    const game = replay(moves);
    if (i === 0) {
      expect(game.status).toBe('playing');
      expect(game.heights[12]).toBe(5);
      continue;
    }
    expect(replay(moves, moves.length - 1).status).toBe('playing');
    expect(game.winner).toBe(1);
    expect(game.winningLines).toHaveLength(1);
    const line = game.winningLines[0];
    expect(line).toHaveLength(4);
    if (example.id === 'diagonal-third-layer') {
      expect(line.map(({ x, y, z }) => [x, y, z])).toEqual([
        [0, 0, 2],
        [1, 1, 2],
        [2, 2, 2],
        [3, 3, 2],
      ]);
      for (const { x, y } of line) expect(game.heights[x + y * 5]).toBe(3);
    }
    expect([line[1].x - line[0].x, line[1].y - line[0].y, line[1].z - line[0].z]).toEqual(
      directions[i - 1],
    );
  }
});
