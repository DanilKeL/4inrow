import { makeMove, SIZE } from '../src/game/core/index.ts';
import { chooseMove } from '../src/game/ai/search.ts';
import {
  dailyPosition,
  DAILY_BOT_DIFFICULTY,
  DAILY_BOT_OPTIONS,
  type DailyChallenge,
} from '../src/game/daily.ts';

export interface DailyMove {
  x: number;
  y: number;
}

/** The only accepted evidence is the player's columns; all bot turns are recomputed. */
export function verifyDailyResult(challenge: DailyChallenge, moves: DailyMove[]): number {
  let game = dailyPosition(challenge);
  if (game.currentPlayer !== 1 || game.status !== 'playing') throw new Error('Invalid challenge');
  if (moves.length === 0 || moves.length > Math.ceil((SIZE ** 3 - game.history.length) / 2))
    throw new Error('Invalid sequence length');
  for (let index = 0; index < moves.length; index++) {
    const move = moves[index];
    if (game.currentPlayer !== 1 || game.status !== 'playing')
      throw new Error('Game finished before the sequence ended');
    const human = makeMove(game, move.x, move.y);
    if (!human.valid) throw new Error('Illegal player move');
    game = human.state;
    if (game.status === 'won') {
      if (game.winner !== 1 || index !== moves.length - 1) throw new Error('Invalid victory');
      return moves.length;
    }
    if (game.status !== 'playing') throw new Error('The result is not a victory');
    const bot = chooseMove(game, DAILY_BOT_DIFFICULTY, DAILY_BOT_OPTIONS);
    if (!bot) throw new Error('No bot move');
    const reply = makeMove(game, bot.x, bot.y);
    if (!reply.valid) throw new Error('Illegal bot move');
    game = reply.state;
    if (game.status !== 'playing') throw new Error('The result is not a victory');
  }
  throw new Error('The game is unfinished');
}
