import { describe, expect, it, vi } from 'vitest';
import { chooseMove } from '../src/game/ai/search';
import { getLegalMoves, makeMove, replay } from '../src/game/core';
import {
  DAILY_BOT_DIFFICULTY,
  DAILY_BOT_OPTIONS,
  dailyDate,
  dailyMoveCount,
  dailyPosition,
  isDailyChallenge,
} from '../src/game/daily';
import { canWinDailyWithinTwoMoves, generateDailyChallenge } from './dailyGenerator';

describe('procedurally generated daily puzzles', () => {
  it('generates a month of distinct complex positions with verified upper-layer wins', () => {
    const boards = new Set<string>();
    const origin = Date.parse('2026-10-09T12:00:00Z');
    for (let offset = 0; offset < 31; offset++) {
      const date = dailyDate(origin + offset * 86400000);
      const generated = generateDailyChallenge(date);
      const { challenge, quality, solution } = generated;
      expect(isDailyChallenge(challenge), date).toBe(true);
      expect(quality.source, date).toBe('generated');
      expect(quality.occupiedLayers, date).toBeGreaterThanOrEqual(3);
      expect(quality.thirdLayerPieces, date).toBeGreaterThanOrEqual(3);
      expect(quality.upperCombinations, date).toBeGreaterThanOrEqual(2);
      expect(solution.length, date).toBeGreaterThanOrEqual(3);
      let state = dailyPosition(challenge);
      expect(state.status).toBe('playing');
      expect(state.currentPlayer).toBe(1);
      expect(dailyMoveCount(state, challenge)).toBe(0);
      boards.add(state.board.join(''));
      // The preset offers neither an immediate win nor a compulsory obvious defense.
      for (const player of [1, 2] as const) {
        for (const move of getLegalMoves(state)) {
          const result = makeMove({ ...state, currentPlayer: player }, move.x, move.y);
          expect(result.valid && result.state.winner === player, date).toBe(false);
        }
      }
      expect(canWinDailyWithinTwoMoves(state), date).toBe(false);
      for (const human of solution) {
        expect(state.currentPlayer).toBe(1);
        const first = makeMove(state, human.x, human.y);
        if (!first.valid) throw new Error(`Invalid daily solution on ${date}`);
        state = first.state;
        if (state.status !== 'playing') break;
        const bot = chooseMove(state, DAILY_BOT_DIFFICULTY, DAILY_BOT_OPTIONS)!;
        const reply = makeMove(state, bot.x, bot.y);
        if (!reply.valid) throw new Error(`Invalid daily bot reply on ${date}`);
        state = reply.state;
      }
      expect(state.winner, date).toBe(1);
      expect(dailyMoveCount(state, challenge)).toBe(solution.length);
      expect(
        state.winningLines.some((line) => line.some((point) => point.z >= 2)),
        date,
      ).toBe(true);
    }
    expect(boards.size).toBe(31);
  }, 60000);

  it('depends only on the date and version, with no randomness or time-based bot decisions', () => {
    const before = generateDailyChallenge('2026-10-09');
    const random = vi.spyOn(Math, 'random').mockImplementation(() => {
      throw new Error('Daily puzzles must not use randomness');
    });
    const clock = vi.spyOn(performance, 'now').mockReturnValue(1e12);
    try {
      generateDailyChallenge('2026-10-10');
      expect(generateDailyChallenge('2026-10-09')).toEqual(before);
    } finally {
      random.mockRestore();
      clock.mockRestore();
    }
  });

  it('detects obvious one-move wins and rejects invalid dates', () => {
    const easy = replay([
      { x: 0, y: 0 },
      { x: 0, y: 1 },
      { x: 1, y: 0 },
      { x: 1, y: 1 },
      { x: 2, y: 0 },
      { x: 4, y: 4 },
    ]);
    expect(canWinDailyWithinTwoMoves(easy)).toBe(true);
    expect(() => generateDailyChallenge('2026-02-30')).toThrow('Invalid daily challenge date');
  });
});
