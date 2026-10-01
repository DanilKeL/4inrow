import { CONNECT, DIRECTIONS, SIZE, type GameState, type Player } from '../core';

export type Difficulty = 'easy' | 'medium' | 'hard';
export interface BotOptions {
  deterministic?: boolean;
  nodeBudget?: number;
}
export interface MoveCandidate {
  x: number;
  y: number;
}
const AREA = SIZE * SIZE;
const WIN = 1_000_000;
const WEIGHTS = [0, 3, 32, 180, WIN];
const other = (player: Player): Player => (player === 1 ? 2 : 1);
const inside = (n: number) => n >= 0 && n < SIZE;
const segments: number[][] = [];
const throughCell: number[][] = Array.from({ length: SIZE ** 3 }, () => []);
for (let z = 0; z < SIZE; z++) {
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      for (const d of DIRECTIONS) {
        if (
          !inside(x + d.x * (CONNECT - 1)) ||
          !inside(y + d.y * (CONNECT - 1)) ||
          !inside(z + d.z * (CONNECT - 1))
        )
          continue;
        const segment = Array.from(
          { length: CONNECT },
          (_, i) => x + d.x * i + (y + d.y * i) * SIZE + (z + d.z * i) * AREA,
        );
        for (const cell of segment) throughCell[cell].push(segments.length);
        segments.push(segment);
      }
    }
  }
}

// Two independent deterministic hashes verify transpositions without copying boards.
let seed = 0x51f15e;
function randomHash(): number {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return seed >>> 0;
}
const hashes = Array.from({ length: SIZE ** 3 * 2 }, () => [randomHash(), randomHash()]);
const centrality = Array.from(
  { length: AREA },
  (_, column) => (4 - Math.abs((column % SIZE) - 2) - Math.abs(Math.floor(column / SIZE) - 2)) * 3,
);

/** Private mutable position. Only lines through a changed cell need updating. */
class Position {
  board: number[];
  heights: number[];
  counts = [new Int8Array(segments.length), new Int8Array(segments.length)];
  score = 0;
  hash = 0;
  lock = 0;
  constructor(state: GameState) {
    this.board = [...state.board];
    this.heights = [...state.heights];
    for (let cell = 0; cell < this.board.length; cell++) {
      const player = this.board[cell];
      if (player) this.update(cell, player as Player, 1);
    }
  }
  private lineScore(line: number): number {
    const a = this.counts[0][line];
    const b = this.counts[1][line];
    return a && b ? 0 : WEIGHTS[a] - WEIGHTS[b];
  }
  private update(cell: number, player: Player, delta: number): void {
    for (const line of throughCell[cell]) {
      this.score -= this.lineScore(line);
      this.counts[player - 1][line] += delta;
      this.score += this.lineScore(line);
    }
    this.score += (player === 1 ? 1 : -1) * delta * centrality[cell % AREA];
    const hash = hashes[cell * 2 + player - 1];
    this.hash ^= hash[0];
    this.lock ^= hash[1];
  }
  legal(): number[] {
    const columns: number[] = [];
    for (let column = 0; column < AREA; column++)
      if (this.heights[column] < SIZE) columns.push(column);
    return columns;
  }
  put(column: number, player: Player): void {
    const cell = column + this.heights[column]++ * AREA;
    this.board[cell] = player;
    this.update(cell, player, 1);
  }
  remove(column: number): void {
    const cell = column + --this.heights[column] * AREA;
    this.update(cell, this.board[cell] as Player, -1);
    this.board[cell] = 0;
  }
  threats(player: Player): number[] {
    const columns: number[] = [];
    for (let column = 0; column < AREA; column++) {
      if (this.heights[column] === SIZE) continue;
      const cell = column + this.heights[column] * AREA;
      if (
        throughCell[cell].some(
          (line) =>
            this.counts[player - 1][line] === CONNECT - 1 &&
            this.counts[other(player) - 1][line] === 0,
        )
      )
        columns.push(column);
    }
    return columns;
  }
  evaluate(player: Player): number {
    let score = this.score;
    for (let line = 0; line < segments.length; line++) {
      const a = this.counts[0][line];
      const b = this.counts[1][line];
      if ((a && b) || Math.max(a, b) < 2) continue;
      // Floating lines need supporting pieces first. A reachable threat is worth more.
      let support = 0;
      for (const cell of segments[line])
        if (!this.board[cell]) support += Math.floor(cell / AREA) - this.heights[cell % AREA];
      const pieces = Math.max(a, b);
      const adjustment =
        support === 0 ? (pieces === 3 ? 700 : 16) : (-WEIGHTS[pieces] * support) / (support + 2);
      score += (a ? 1 : -1) * adjustment;
    }
    return player === 1 ? score : -score;
  }
  ordered(player: Player, columns = this.legal(), preferred = -1): number[] {
    return columns
      .map((column) => {
        this.put(column, player);
        const score = this.score * (player === 1 ? 1 : -1);
        this.remove(column);
        return { column, score: score + (column === preferred ? WIN * 2 : 0) };
      })
      .sort((a, b) => b.score - a.score)
      .map(({ column }) => column);
  }
}

// Also protect easy mode from giving the opponent a winning square directly above its move.
function candidates(position: Position, player: Player): Array<{ column: number; score: number }> {
  return position
    .legal()
    .map((column) => {
      position.put(column, player);
      const enemyWins = position.threats(other(player)).length;
      const ownWins = position.threats(player).length;
      const score = enemyWins
        ? -WIN
        : ownWins >= 2
          ? WIN
          : position.evaluate(player) + ownWins * 1200;
      position.remove(column);
      return { column, score };
    })
    .sort((a, b) => b.score - a.score);
}
const TIMEOUT = Symbol('search deadline');
interface Entry {
  lock: number;
  turn: Player;
  depth: number;
  score: number;
  bound: 'exact' | 'lower' | 'upper';
  move: number;
}
function searchMove(
  position: Position,
  player: Player,
  difficulty: 'medium' | 'hard',
  fallback: number,
  roots: number[],
  options: BotOptions,
): number {
  const deadline = options.deterministic
    ? Infinity
    : performance.now() + (difficulty === 'hard' ? 650 : 180);
  const maxDepth = difficulty === 'hard' ? 8 : 4;
  const table = new Map<number, Entry>();
  let chosen = fallback;
  // Scores are comparable only within the same fully completed search depth.
  const margin = difficulty === 'hard' ? 24 : 60;
  let alternatives: Array<{ column: number; score: number }> = [];
  let visited = 0;
  function negamax(turn: Player, depth: number, alpha: number, beta: number, ply: number): number {
    visited++;
    if (
      options.deterministic
        ? visited > (options.nodeBudget ?? 6000)
        : (visited & 31) === 0 && performance.now() >= deadline
    )
      throw TIMEOUT;
    // Resolve tactics BEFORE the depth cutoff. Two different winning columns
    // cannot both be blocked by a single placement, including vertical stacks.
    if (position.threats(turn).length) return WIN - ply;
    const blocks = position.threats(other(turn));
    if (blocks.length >= 2) return -WIN + ply + 1;
    const legal = blocks.length ? blocks : position.legal();
    if (!legal.length) return 0;
    // Continue forced defenses up to six plies beyond the ordinary horizon.
    if (depth <= 0 && (!blocks.length || depth <= -6)) return position.evaluate(turn);
    const cached = table.get(position.hash);
    const entry = cached?.lock === position.lock && cached.turn === turn ? cached : undefined;
    if (depth > 0 && entry && entry.depth >= depth) {
      if (entry.bound === 'exact') return entry.score;
      if (entry.bound === 'lower') alpha = Math.max(alpha, entry.score);
      else beta = Math.min(beta, entry.score);
      if (alpha >= beta) return entry.score;
    }
    const originalAlpha = alpha;
    const originalBeta = beta;
    let best = -Infinity;
    let bestMove = legal[0];
    for (const column of position.ordered(turn, legal, entry?.move)) {
      position.put(column, turn);
      let score: number;
      try {
        score = -negamax(other(turn), depth - 1, -beta, -alpha, ply + 1);
      } finally {
        position.remove(column);
      }
      if (score > best) {
        best = score;
        bestMove = column;
      }
      alpha = Math.max(alpha, score);
      if (alpha >= beta) break;
    }
    if (depth > 0 && table.size < 60_000)
      table.set(position.hash, {
        lock: position.lock,
        turn,
        depth,
        score: best,
        move: bestMove,
        bound: best <= originalAlpha ? 'upper' : best >= originalBeta ? 'lower' : 'exact',
      });
    return best;
  }
  // Commit completed iterations only; timeouts unwind every temporary placement.
  for (let depth = 1; depth <= maxDepth; depth++) {
    let best = -Infinity;
    let iterationMove = chosen;
    const scores: Array<{ column: number; score: number; exact: boolean }> = [];
    try {
      for (const column of position.ordered(player, roots, chosen)) {
        if (performance.now() >= deadline) throw TIMEOUT;
        position.put(column, player);
        let score: number;
        const threshold = best - margin;
        try {
          // A wider root window obtains exact scores for near-best alternatives.
          // Fail-low results are upper bounds and must never enter the random pool.
          score = -negamax(other(player), depth - 1, -Infinity, -threshold, 1);
        } finally {
          position.remove(column);
        }
        scores.push({ column, score, exact: score > threshold });
        if (score > best) {
          best = score;
          iterationMove = column;
        }
      }
      chosen = iterationMove;
      alternatives =
        depth < 2 || Math.abs(best) > WIN - 100
          ? []
          : scores
              .filter(
                (move) =>
                  move.exact &&
                  move.column !== chosen &&
                  move.score >= best - margin &&
                  move.score > -WIN + 100,
              )
              .sort((a, b) => b.score - a.score)
              .slice(0, 3);
      if (Math.abs(best) > WIN - 100) break;
    } catch (error) {
      if (error !== TIMEOUT) throw error;
      break;
    }
  }
  const chance = difficulty === 'hard' ? 0.25 : 0.35;
  if (!options.deterministic && alternatives.length && Math.random() < chance) {
    return alternatives[Math.floor(Math.random() * alternatives.length)].column;
  }
  return chosen;
}

/** Synchronous strategy, executed inside a Worker by requestBotMove. */
export function chooseMove(
  state: GameState,
  difficulty: Difficulty,
  options: BotOptions = {},
): MoveCandidate | null {
  if (state.status !== 'playing') return null;
  const position = new Position(state);
  if (!position.legal().length) return null;
  const player = state.currentPlayer;
  const wins = position.threats(player);
  const blocks = position.threats(other(player));
  let column: number;
  if (wins.length) column = wins[0];
  else if (blocks.length) column = blocks[0];
  else {
    const ranked = candidates(position, player);
    if (ranked[0].score === WIN) column = ranked[0].column;
    else if (difficulty === 'easy') {
      const safe = ranked.filter((move) => move.score > -WIN);
      const pool = (safe.length ? safe : ranked).slice(0, 4);
      column = pool[options.deterministic ? 0 : Math.floor(Math.random() * pool.length)].column;
    } else {
      const safe = ranked.filter((move) => move.score > -WIN);
      column = searchMove(
        position,
        player,
        difficulty,
        ranked[0].column,
        (safe.length ? safe : ranked).map((move) => move.column),
        options,
      );
    }
  }
  return { x: column % SIZE, y: Math.floor(column / SIZE) };
}
