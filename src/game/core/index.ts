/** Portable, deterministic rules. Coordinates are zero-based; z is height. */
export type Player = 1 | 2;
export interface Position {
  x: number;
  y: number;
  z: number;
}
export interface Move extends Position {
  player: Player;
  index: number;
}
export interface GameState {
  board: number[];
  heights: number[];
  currentPlayer: Player;
  history: Move[];
  status: 'playing' | 'won' | 'draw';
  winner: Player | null;
  winningLines: Position[][];
}
export type MoveResult =
  { valid: true; state: GameState; move: Move } | { valid: false; reason: string };

export const SIZE = 5;
export const CONNECT = 4;
/** One representative of each opposite pair of the 26 unit directions. */
export const DIRECTIONS: readonly Readonly<Position>[] = [
  { x: 1, y: 0, z: 0 },
  { x: 0, y: 1, z: 0 },
  { x: 0, y: 0, z: 1 },
  { x: 1, y: 1, z: 0 },
  { x: 1, y: -1, z: 0 },
  { x: 1, y: 0, z: 1 },
  { x: 1, y: 0, z: -1 },
  { x: 0, y: 1, z: 1 },
  { x: 0, y: 1, z: -1 },
  { x: 1, y: 1, z: 1 },
  { x: 1, y: 1, z: -1 },
  { x: 1, y: -1, z: 1 },
  { x: 1, y: -1, z: -1 },
];

const coordinate = (n: number) => Number.isInteger(n) && n >= 0 && n < SIZE;
export const boardIndex = ({ x, y, z }: Position) => x + y * SIZE + z * SIZE * SIZE;
const inside = ({ x, y, z }: Position) => coordinate(x) && coordinate(y) && coordinate(z);

export function createGame(firstPlayer: Player = 1): GameState {
  return {
    board: Array<number>(SIZE ** 3).fill(0),
    heights: Array<number>(SIZE ** 2).fill(0),
    currentPlayer: firstPlayer,
    history: [],
    status: 'playing',
    winner: null,
    winningLines: [],
  };
}

/** Returns whole contiguous lines, including all five pieces when applicable. */
export function detectWinningLines(board: number[], last: Position, player: Player): Position[][] {
  if (!inside(last) || board[boardIndex(last)] !== player) return [];
  const lines: Position[][] = [];
  for (const direction of DIRECTIONS) {
    const line: Position[] = [{ x: last.x, y: last.y, z: last.z }];
    for (const sign of [-1, 1]) {
      for (let distance = 1; distance < SIZE; distance++) {
        const position = {
          x: last.x + direction.x * distance * sign,
          y: last.y + direction.y * distance * sign,
          z: last.z + direction.z * distance * sign,
        };
        if (!inside(position) || board[boardIndex(position)] !== player) break;
        if (sign < 0) line.unshift(position);
        else line.push(position);
      }
    }
    if (line.length >= CONNECT) lines.push(line);
  }
  return lines;
}

export function makeMove(state: GameState, x: number, y: number): MoveResult {
  if (state.status !== 'playing') return { valid: false, reason: 'Game is already finished' };
  if (!coordinate(x) || !coordinate(y))
    return { valid: false, reason: 'Invalid column coordinates' };
  const column = x + y * SIZE;
  const z = state.heights[column];
  if (z >= SIZE) return { valid: false, reason: 'Column is full' };
  const move: Move = { x, y, z, player: state.currentPlayer, index: state.history.length };
  const board = [...state.board];
  const heights = [...state.heights];
  board[boardIndex(move)] = move.player;
  heights[column] = z + 1;
  const winningLines = detectWinningLines(board, move, move.player);
  const status = winningLines.length
    ? 'won'
    : heights.every((height) => height === SIZE)
      ? 'draw'
      : 'playing';
  return {
    valid: true,
    move,
    state: {
      board,
      heights,
      history: [...state.history, move],
      winningLines,
      status,
      winner: status === 'won' ? move.player : null,
      currentPlayer: status === 'playing' ? (move.player === 1 ? 2 : 1) : move.player,
    },
  };
}

export function getLegalMoves(state: GameState): Array<{ x: number; y: number }> {
  if (state.status !== 'playing') return [];
  return state.heights.flatMap((height, column) =>
    height < SIZE ? [{ x: column % SIZE, y: Math.floor(column / SIZE) }] : [],
  );
}

/** Rejects illegal history rather than silently truncating a corrupted saved game. */
export function replay(
  moves: Array<{ x: number; y: number; player?: Player }>,
  count = moves.length,
  firstPlayer: Player = moves[0]?.player ?? 1,
): GameState {
  if (
    !Array.isArray(moves) ||
    !Number.isInteger(count) ||
    count < 0 ||
    count > moves.length ||
    count > SIZE ** 3
  ) {
    throw new Error('Invalid replay length');
  }
  if (firstPlayer !== 1 && firstPlayer !== 2) throw new Error('Invalid first player');
  let state = createGame(firstPlayer);
  for (let index = 0; index < count; index++) {
    const move = moves[index];
    if (!move || typeof move !== 'object') throw new Error(`Invalid move at index ${index}`);
    const result = makeMove(state, move.x, move.y);
    if (!result.valid) throw new Error(`Invalid move at index ${index}: ${result.reason}`);
    state = result.state;
  }
  return state;
}

export function undo(state: GameState): GameState {
  return replay(state.history, Math.max(0, state.history.length - 1));
}

export function serialize(state: GameState): string {
  return JSON.stringify({
    version: 1,
    size: SIZE,
    connect: CONNECT,
    firstPlayer: state.history[0]?.player ?? state.currentPlayer,
    moves: state.history.map(({ x, y }) => ({ x, y })),
  });
}

export function deserialize(json: string): GameState {
  const saved: unknown = JSON.parse(json);
  if (!saved || typeof saved !== 'object' || Array.isArray(saved))
    throw new Error('Invalid saved game');
  const data = saved as Record<string, unknown>;
  if (
    data.version !== 1 ||
    data.size !== SIZE ||
    data.connect !== CONNECT ||
    !Array.isArray(data.moves) ||
    data.moves.length > SIZE ** 3
  ) {
    throw new Error('Unsupported or invalid saved game');
  }
  const moves = data.moves.map((entry: unknown) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry))
      throw new Error('Invalid saved move');
    const move = entry as Record<string, unknown>;
    if (
      typeof move.x !== 'number' ||
      typeof move.y !== 'number' ||
      !coordinate(move.x) ||
      !coordinate(move.y)
    ) {
      throw new Error('Invalid saved coordinates');
    }
    return { x: move.x, y: move.y };
  });
  if (data.firstPlayer !== undefined && data.firstPlayer !== 1 && data.firstPlayer !== 2)
    throw new Error('Invalid first player');
  return replay(moves, moves.length, data.firstPlayer ?? 1);
}
