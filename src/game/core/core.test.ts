import { describe, expect, it } from 'vitest';
import {
  boardIndex,
  createGame,
  deserialize,
  detectWinningLines,
  DIRECTIONS,
  getLegalMoves,
  makeMove,
  replay,
  serialize,
  undo,
  type GameState,
  type Position,
} from './index';

function play(state: GameState, x: number, y: number): GameState {
  const result = makeMove(state, x, y);
  if (!result.valid) throw new Error(result.reason);
  return result.state;
}

const winMoves = [
  { x: 0, y: 0 },
  { x: 0, y: 4 },
  { x: 1, y: 0 },
  { x: 1, y: 4 },
  { x: 2, y: 0 },
  { x: 2, y: 4 },
  { x: 3, y: 0 },
];

describe('3D victory detection', () => {
  it('covers exactly 13 unique undirected axes', () => {
    expect(DIRECTIONS).toHaveLength(13);
    const keys = new Set(DIRECTIONS.map((d) => JSON.stringify(d)));
    expect(keys.size).toBe(13);
    for (const d of DIRECTIONS) {
      expect(keys.has(JSON.stringify({ x: -d.x, y: -d.y, z: -d.z }))).toBe(false);
    }
  });

  for (const direction of DIRECTIONS) {
    describe(`direction ${JSON.stringify(direction)}`, () => {
      for (const length of [4, 5]) {
        const positions: Position[] = Array.from({ length }, (_, i) => ({
          x: (direction.x < 0 ? 4 : 0) + direction.x * i,
          y: (direction.y < 0 ? 4 : 0) + direction.y * i,
          z: (direction.z < 0 ? 4 : 0) + direction.z * i,
        }));
        it(`finds a ${length}-piece line from either end or middle for both players`, () => {
          for (const player of [1, 2] as const) {
            const board = createGame().board;
            positions.forEach((p) => {
              board[boardIndex(p)] = player;
            });
            for (const last of positions) {
              const lines = detectWinningLines(board, last, player);
              expect(lines).toHaveLength(1);
              expect(lines[0]).toEqual(positions);
            }
          }
        });
      }
      it('does not count interrupted or three-piece lines', () => {
        const positions = Array.from({ length: 5 }, (_, i) => ({
          x: (direction.x < 0 ? 4 : 0) + direction.x * i,
          y: (direction.y < 0 ? 4 : 0) + direction.y * i,
          z: (direction.z < 0 ? 4 : 0) + direction.z * i,
        }));
        const board = createGame().board;
        positions.forEach((p) => {
          board[boardIndex(p)] = 1;
        });
        board[boardIndex(positions[2])] = 2;
        expect(detectWinningLines(board, positions[0], 1)).toEqual([]);
        board.fill(0);
        positions.slice(0, 3).forEach((p) => {
          board[boardIndex(p)] = 1;
        });
        expect(detectWinningLines(board, positions[1], 1)).toEqual([]);
      });
    });
  }

  it('returns all simultaneous winning lines through the last move', () => {
    const board = createGame().board;
    for (let i = 0; i < 5; i++) {
      board[boardIndex({ x: i, y: 2, z: 2 })] = 1;
      board[boardIndex({ x: 2, y: i, z: 2 })] = 1;
      board[boardIndex({ x: 2, y: 2, z: i })] = 1;
    }
    const lines = detectWinningLines(board, { x: 2, y: 2, z: 2 }, 1);
    expect(lines).toHaveLength(3);
    expect(lines.every((line) => line.length === 5)).toBe(true);
  });

  it('does not wrap an array row into the next row', () => {
    const board = createGame().board;
    for (const index of [3, 4, 5, 6]) board[index] = 1;
    expect(detectWinningLines(board, { x: 4, y: 0, z: 0 }, 1)).toEqual([]);
  });

  it('ignores empty, opponent and out-of-bounds last positions', () => {
    const board = createGame().board;
    expect(detectWinningLines(board, { x: 0, y: 0, z: 0 }, 1)).toEqual([]);
    board[0] = 2;
    expect(detectWinningLines(board, { x: 0, y: 0, z: 0 }, 1)).toEqual([]);
    expect(detectWinningLines(board, { x: -1, y: 0, z: 0 }, 1)).toEqual([]);
  });
});

describe('gravity, turns and legal moves', () => {
  it('starts with 125 empty cells, 25 columns and player one', () => {
    const state = createGame();
    expect(state.board).toEqual(Array(125).fill(0));
    expect(state.heights).toEqual(Array(25).fill(0));
    expect(state.currentPlayer).toBe(1);
    expect(state.status).toBe('playing');
    expect(getLegalMoves(state)).toHaveLength(25);
  });

  it('stacks at the lowest free height and alternates players', () => {
    let state = createGame();
    for (let z = 0; z < 5; z++) {
      state = play(state, 3, 2);
      expect(state.history[z]).toEqual({ x: 3, y: 2, z, player: (z % 2) + 1, index: z });
      expect(state.board[3 + 2 * 5 + z * 25]).toBe((z % 2) + 1);
      expect(state.heights[13]).toBe(z + 1);
    }
    expect(makeMove(state, 3, 2)).toEqual({ valid: false, reason: 'Column is full' });
    expect(getLegalMoves(state)).toHaveLength(24);
    expect(getLegalMoves(state)).not.toContainEqual({ x: 3, y: 2 });
  });

  it.each([-1, 5, 1.5, NaN, Infinity, -Infinity])('rejects invalid coordinate %s', (value) => {
    const state = createGame();
    expect(makeMove(state, value, 0).valid).toBe(false);
    expect(makeMove(state, 0, value).valid).toBe(false);
    expect(state.history).toEqual([]);
  });

  it('does not mutate previous snapshots, including a frozen input', () => {
    const state = play(createGame(), 2, 2);
    const original = structuredClone(state);
    Object.freeze(state.board);
    Object.freeze(state.heights);
    Object.freeze(state.history);
    Object.freeze(state);
    const next = play(state, 2, 2);
    expect(state).toEqual(original);
    expect(next.board).not.toBe(state.board);
    expect(next.heights).not.toBe(state.heights);
    expect(next.history).not.toBe(state.history);
  });

  it('finishes at the first win and rejects further moves', () => {
    const state = replay(winMoves);
    expect(state.status).toBe('won');
    expect(state.winner).toBe(1);
    expect(state.winningLines).toHaveLength(1);
    expect(state.winningLines[0]).toHaveLength(4);
    expect(getLegalMoves(state)).toEqual([]);
    expect(makeMove(state, 4, 4).valid).toBe(false);
  });

  it('detects a legal vertical win with supporting turns elsewhere', () => {
    const state = replay([
      { x: 2, y: 2 },
      { x: 0, y: 0 },
      { x: 2, y: 2 },
      { x: 4, y: 0 },
      { x: 2, y: 2 },
      { x: 0, y: 4 },
      { x: 2, y: 2 },
    ]);
    expect(state.winner).toBe(1);
    expect(state.winningLines[0].map((p) => p.z)).toEqual([0, 1, 2, 3]);
  });

  it('builds a true space-diagonal victory through legal alternating support stacks', () => {
    // Ten pieces are needed to support heights 0/1/2/3; eleven is the minimum
    // possible ply count for player one to complete this diagonal.
    const moves = [
      { x: 0, y: 0 },
      { x: 1, y: 1 },
      { x: 1, y: 1 },
      { x: 2, y: 2 },
      { x: 2, y: 2 },
      { x: 3, y: 3 },
      { x: 2, y: 2 },
      { x: 3, y: 3 },
      { x: 3, y: 3 },
      { x: 4, y: 0 },
      { x: 3, y: 3 },
    ];
    for (let count = 0; count < moves.length; count++) {
      expect(replay(moves, count).status).toBe('playing');
    }
    const state = replay(moves);
    expect(state.status).toBe('won');
    expect(state.winner).toBe(1);
    expect(state.winningLines).toEqual([
      [
        { x: 0, y: 0, z: 0 },
        { x: 1, y: 1, z: 1 },
        { x: 2, y: 2, z: 2 },
        { x: 3, y: 3, z: 3 },
      ],
    ]);
    expect(state.history[10]).toEqual({ x: 3, y: 3, z: 3, player: 1, index: 10 });
    for (const move of state.history) {
      for (let z = 0; z < move.z; z++) {
        expect(state.board[boardIndex({ ...move, z })]).not.toBe(0);
      }
    }
  });

  it('plays a complete legal 125-move draw, without a winning line anywhere', () => {
    // A two-coloring without monochromatic four-segments, ordered to obey gravity and turns.
    const columns = [
      2, 7, 11, 14, 24, 8, 21, 1, 6, 14, 15, 9, 3, 20, 14, 16, 1, 17, 5, 23, 13, 16, 17, 18, 2, 21,
      17, 6, 7, 3, 23, 8, 8, 10, 13, 5, 12, 3, 3, 3, 14, 14, 20, 20, 5, 1, 16, 13, 22, 12, 20, 23,
      18, 1, 24, 1, 4, 22, 22, 24, 15, 24, 9, 2, 17, 13, 0, 24, 10, 12, 10, 12, 10, 17, 6, 23, 4,
      15, 11, 5, 11, 11, 22, 21, 2, 21, 20, 7, 2, 9, 11, 16, 4, 16, 12, 23, 21, 5, 13, 4, 8, 10, 7,
      9, 7, 9, 8, 18, 18, 0, 0, 15, 6, 22, 15, 0, 19, 18, 4, 6, 0, 19, 19, 19, 19,
    ];
    const state = replay(columns.map((column) => ({ x: column % 5, y: Math.floor(column / 5) })));
    expect(state.status).toBe('draw');
    expect(state.history).toHaveLength(125);
    expect(state.winner).toBeNull();
    expect(state.winningLines).toEqual([]);
    expect(state.heights).toEqual(Array(25).fill(5));
    expect(getLegalMoves(state)).toEqual([]);
    for (const move of state.history)
      expect(detectWinningLines(state.board, move, move.player)).toEqual([]);
    expect(makeMove(state, 0, 0).valid).toBe(false);
    expect(deserialize(serialize(state))).toEqual(state);
    const prior = undo(state);
    expect(prior.status).toBe('playing');
    expect(prior.history).toHaveLength(124);
    expect(getLegalMoves(prior)).toEqual([{ x: 4, y: 3 }]);
  });
});

describe('history, persistence and recovery', () => {
  it('undoes a winning move and restores the correct turn', () => {
    const won = replay(winMoves);
    const previous = undo(won);
    expect(previous).toEqual(replay(winMoves, 6));
    expect(previous.status).toBe('playing');
    expect(previous.currentPlayer).toBe(1);
    expect(previous.winner).toBeNull();
    expect(previous.winningLines).toEqual([]);
    expect(play(previous, 3, 0)).toEqual(won);
    expect(won.history).toHaveLength(7);
  });

  it('undo on an empty game is safe', () => {
    expect(undo(createGame())).toEqual(createGame());
  });

  it('replays every prefix without changing the source history', () => {
    const moves = structuredClone(winMoves);
    for (let count = 0; count <= moves.length; count++) {
      const state = replay(moves, count);
      expect(state.history).toHaveLength(count);
      expect(state.board.filter(Boolean)).toHaveLength(count);
    }
    expect(moves).toEqual(winMoves);
  });

  it.each([-1, 8, 0.5, NaN, Infinity])('rejects invalid replay length %s', (count) => {
    expect(() => replay(winMoves, count)).toThrow();
  });

  it('round-trips empty, stacked and finished games', () => {
    const states = [createGame(), play(play(createGame(), 2, 2), 2, 2), replay(winMoves)];
    for (const state of states) expect(deserialize(serialize(state))).toEqual(state);
  });

  it.each(['null', '{}', '[]', '"hello"', '{', '{"version":2,"size":5,"connect":4,"moves":[]}'])(
    'rejects malformed or incompatible save %s',
    (json) => {
      expect(() => deserialize(json)).toThrow();
    },
  );

  it.each([null, [], {}, { x: '1', y: 0 }, { x: 1.5, y: 0 }, { x: -1, y: 0 }, { x: 0, y: 5 }])(
    'rejects invalid saved move %j',
    (move) => {
      const json = JSON.stringify({ version: 1, size: 5, connect: 4, moves: [move] });
      expect(() => deserialize(json)).toThrow();
    },
  );

  it('rejects a sixth stacked move and moves following victory', () => {
    expect(() => replay(Array.from({ length: 6 }, () => ({ x: 0, y: 0 })))).toThrow(
      'Column is full',
    );
    expect(() => replay([...winMoves, { x: 4, y: 4 }])).toThrow('already finished');
  });

  it('rejects histories exceeding the board capacity', () => {
    expect(() =>
      deserialize(
        JSON.stringify({
          version: 1,
          size: 5,
          connect: 4,
          moves: Array(126).fill({ x: 0, y: 0 }),
        }),
      ),
    ).toThrow();
  });

  it('ignores forged derived state and reconstructs it from legal moves', () => {
    const json = JSON.stringify({
      ...JSON.parse(serialize(createGame())),
      winner: 2,
      board: [2],
      currentPlayer: 2,
    });
    expect(deserialize(json)).toEqual(createGame());
  });
});
