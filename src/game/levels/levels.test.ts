import { describe, expect, it, vi } from 'vitest';
import { makeMove, getLegalMoves, replay } from '../core';
import { chooseMove } from '../ai/search';
import { LEVELS, LEVEL_BOT_OPTIONS, levelPosition, levelMoveCount } from './index';
import solutions from './solutions.json';

describe('40 fixed solo levels', () => {
  it('uses distinct legal nonterminal presets with supported pieces and the human to move', () => {
    expect(LEVELS).toHaveLength(40);
    expect(new Set(LEVELS.map((level) => level.id)).size).toBe(40);
    const boards = new Set<string>();
    for (const level of LEVELS) {
      const state = levelPosition(level);
      expect(state.status).toBe('playing');
      expect(state.currentPlayer).toBe(1);
      expect(state.history.length).toBeGreaterThanOrEqual(10);
      expect(levelMoveCount(state, level)).toBe(0);
      boards.add(state.board.join(''));
      for (let c = 0; c < 25; c++)
        for (let z = 0; z < state.heights[c]; z++) expect(state.board[c + z * 25]).not.toBe(0);
    }
    expect(boards.size).toBe(40);
  });

  it('can win every level against the exact production bot policy', () => {
    for (const level of LEVELS) {
      let state = levelPosition(level);
      const solution = solutions.find((s) => s.id === level.id)!.solution;
      for (const human of solution) {
        expect(state.currentPlayer).toBe(1);
        const result = makeMove(state, human.x, human.y);
        if (!result.valid) throw new Error(`Invalid solution in level ${level.id}`);
        state = result.state;
        if (state.status !== 'playing') break;
        const bot = chooseMove(state, 'medium', LEVEL_BOT_OPTIONS)!;
        const reply = makeMove(state, bot.x, bot.y);
        if (!reply.valid) throw new Error(`Invalid reply in level ${level.id}`);
        state = reply.state;
      }
      expect(state.winner, `Level ${level.id}`).toBe(1);
      expect(levelMoveCount(state, level)).toBe(solution.length);
    }
  }, 30000);

  it('is deterministic independently of clocks, random values and previous positions', () => {
    const random = vi.spyOn(Math, 'random').mockImplementation(() => {
      throw new Error('Randomness is forbidden in levels');
    });
    const clock = vi.spyOn(performance, 'now');
    try {
      for (const level of LEVELS.filter((l) => l.id % 4 === 0)) {
        const initial = levelPosition(level);
        const move = getLegalMoves(initial)[2];
        const result = makeMove(initial, move.x, move.y);
        if (!result.valid || result.state.status !== 'playing') continue;
        const before = JSON.stringify(result.state);
        clock.mockReturnValue(0);
        const first = chooseMove(result.state, 'medium', LEVEL_BOT_OPTIONS);
        chooseMove(replay([{ x: 0, y: 0 }]), 'medium', LEVEL_BOT_OPTIONS);
        clock.mockReturnValue(1e12);
        expect(chooseMove(result.state, 'medium', LEVEL_BOT_OPTIONS)).toEqual(first);
        expect(JSON.stringify(result.state)).toBe(before);
      }
    } finally {
      random.mockRestore();
      clock.mockRestore();
    }
  });
});
