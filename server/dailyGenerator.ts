import {
  CONNECT,
  DIRECTIONS,
  SIZE,
  createGame,
  getLegalMoves,
  makeMove,
  replay,
  type GameState,
} from '../src/game/core';
import { chooseMove } from '../src/game/ai/search';
import {
  DAILY_BOT_DIFFICULTY,
  DAILY_BOT_OPTIONS,
  dailyExpiresAt,
  type DailyChallenge,
  type DailyPoint,
} from '../src/game/daily';
import { LEVELS } from '../src/game/levels';
import levelSolutions from '../src/game/levels/solutions.json';

export interface GeneratedDailyChallenge {
  challenge: DailyChallenge;
  /** Private proof of solvability. Never include this field in a public response. */
  solution: DailyPoint[];
  quality: {
    source: 'generated' | 'fallback';
    pieces: number;
    occupiedLayers: number;
    thirdLayerPieces: number;
    upperCombinations: number;
    solutionMoves: number;
    minimumMoves: 3;
  };
}

// Bounded, date-seeded work: the server runs this once per date in a worker.
const MAX_CANDIDATES = 160;
const MAX_SOLUTION_MOVES = 10;
const HUMAN_SEARCH_OPTIONS = { deterministic: true, nodeBudget: 16000 } as const;
const AREA = SIZE * SIZE;
const upperSegments: number[][] = [];
for (let z = 0; z < SIZE; z++) {
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      for (const direction of DIRECTIONS) {
        const end = {
          x: x + direction.x * (CONNECT - 1),
          y: y + direction.y * (CONNECT - 1),
          z: z + direction.z * (CONNECT - 1),
        };
        if (
          Object.values(end).some((coordinate) => coordinate < 0 || coordinate >= SIZE) ||
          Math.max(z, end.z) < 2
        )
          continue;
        upperSegments.push(
          Array.from(
            { length: CONNECT },
            (_, offset) =>
              x +
              direction.x * offset +
              (y + direction.y * offset) * SIZE +
              (z + direction.z * offset) * AREA,
          ),
        );
      }
    }
  }
}

function seededRandom(date: string): () => number {
  let seed = 0x811c9dc5;
  for (const character of `four-daily-v1:${date}`)
    seed = Math.imul(seed ^ character.charCodeAt(0), 0x01000193);
  seed ||= 0x4441494c;
  return () => {
    seed ^= seed << 13;
    seed ^= seed >>> 17;
    seed ^= seed << 5;
    return (seed >>> 0) / 4294967296;
  };
}

function hasImmediateWin(state: GameState, player = state.currentPlayer): boolean {
  const position = player === state.currentPlayer ? state : { ...state, currentPlayer: player };
  return getLegalMoves(position).some(({ x, y }) => {
    const result = makeMove(position, x, y);
    return result.valid && result.state.winner === player;
  });
}

function upperCombinationCount(state: GameState): number {
  return upperSegments.filter((segment) => {
    let human = 0;
    let bot = 0;
    for (const cell of segment) {
      if (state.board[cell] === 1) human++;
      if (state.board[cell] === 2) bot++;
    }
    return (human >= 2 && bot === 0) || (bot >= 2 && human === 0);
  }).length;
}

function candidatePosition(random: () => number): GameState | null {
  let state = createGame();
  const pieces = 24 + Math.floor(random() * 10) * 2;
  for (let index = 0; index < pieces; index++) {
    // Both sides avoid giving away a direct win while constructing the preset.
    const safe = getLegalMoves(state).flatMap(({ x, y }) => {
      const result = makeMove(state, x, y);
      return result.valid && result.state.status === 'playing' && !hasImmediateWin(result.state)
        ? [result.state]
        : [];
    });
    if (!safe.length) return null;
    state = safe[Math.floor(random() * safe.length)];
  }
  if (
    state.heights.filter((height) => height >= 3).length < 3 ||
    state.heights.filter((height) => height >= 2).length < 6 ||
    hasImmediateWin(state, 1) ||
    hasImmediateWin(state, 2) ||
    upperCombinationCount(state) < 2
  )
    return null;
  return state;
}

/** Exhaustively rule out every possible one- or two-move human win against this bot. */
export function canWinDailyWithinTwoMoves(initial: GameState): boolean {
  for (const human of getLegalMoves(initial)) {
    const first = makeMove(initial, human.x, human.y);
    if (!first.valid) continue;
    if (first.state.winner === 1) return true;
    const bot = chooseMove(first.state, DAILY_BOT_DIFFICULTY, DAILY_BOT_OPTIONS);
    if (!bot) continue;
    const reply = makeMove(first.state, bot.x, bot.y);
    if (!reply.valid || reply.state.status !== 'playing') continue;
    if (hasImmediateWin(reply.state, 1)) return true;
  }
  return false;
}

function playSolution(initial: GameState, script?: DailyPoint[]): DailyPoint[] | null {
  let state = initial;
  const solution: DailyPoint[] = [];
  for (let index = 0; index < MAX_SOLUTION_MOVES && state.status === 'playing'; index++) {
    const human = script ? script[index] : chooseMove(state, 'hard', HUMAN_SEARCH_OPTIONS);
    if (!human) break;
    const first = makeMove(state, human.x, human.y);
    if (!first.valid) return null;
    solution.push({ x: human.x, y: human.y });
    state = first.state;
    if (state.status !== 'playing') break;
    const bot = chooseMove(state, DAILY_BOT_DIFFICULTY, DAILY_BOT_OPTIONS);
    if (!bot) return null;
    const reply = makeMove(state, bot.x, bot.y);
    if (!reply.valid) return null;
    state = reply.state;
  }
  return state.winner === 1 &&
    solution.length >= 3 &&
    state.winningLines.some((line) => line.some((point) => point.z >= 2))
    ? solution
    : null;
}

function transform(point: DailyPoint, orientation: number): DailyPoint {
  let x = orientation >= 4 ? SIZE - 1 - point.x : point.x;
  let y = point.y;
  for (let rotation = 0; rotation < orientation % 4; rotation++) [x, y] = [SIZE - 1 - y, x];
  return { x, y };
}

function result(
  date: string,
  position: GameState,
  solution: DailyPoint[],
  source: 'generated' | 'fallback',
): GeneratedDailyChallenge {
  return {
    challenge: {
      id: `daily-1-${date}`,
      date,
      version: 1,
      preset: position.history.map(({ x, y }) => ({ x, y })),
      expiresAt: dailyExpiresAt(date),
    },
    solution,
    quality: {
      source,
      pieces: position.history.length,
      occupiedLayers: Math.max(...position.heights),
      thirdLayerPieces: position.heights.filter((height) => height >= 3).length,
      upperCombinations: upperCombinationCount(position),
      solutionMoves: solution.length,
      minimumMoves: 3,
    },
  };
}

/** Same date + version always produces identical legal presets and bot replies. */
export function generateDailyChallenge(date: string): GeneratedDailyChallenge {
  dailyExpiresAt(date);
  const random = seededRandom(date);
  for (let attempt = 0; attempt < MAX_CANDIDATES; attempt++) {
    const position = candidatePosition(random);
    if (!position) continue;
    const solution = playSolution(position);
    if (!solution || canWinDailyWithinTwoMoves(position)) continue;
    return result(date, position, solution, 'generated');
  }

  // An independently validated deep position guarantees availability if all candidates fail.
  // Rotations are rechecked because deterministic move ordering can change after rotation.
  const fallback = LEVELS.find((level) => level.id === 37)!;
  const script = levelSolutions.find((level) => level.id === fallback.id)!.solution;
  const orientations = [0, 1, 6, 7];
  const start = Math.floor(random() * orientations.length);
  for (let offset = 0; offset < orientations.length; offset++) {
    const orientation = orientations[(start + offset) % orientations.length];
    const position = replay(fallback.preset.map((point) => transform(point, orientation)));
    const solution = playSolution(
      position,
      script.map((point) => transform(point, orientation)),
    );
    if (solution && !canWinDailyWithinTwoMoves(position))
      return result(date, position, solution, 'fallback');
  }
  throw new Error('No verified daily challenge is available for this version');
}
