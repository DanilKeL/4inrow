import { afterEach, describe, expect, it, vi } from 'vitest';
import { createGame, getLegalMoves, makeMove, type GameState, type Player } from '../core';
import { chooseMove, requestBotMove, type Difficulty } from './index';

function play(columns: Array<[number, number]>): GameState {
  let state = createGame();
  for (const [x, y] of columns) {
    const result = makeMove(state, x, y);
    if (!result.valid) throw new Error(result.reason);
    state = result.state;
  }
  return state;
}

function after(state: GameState, move: { x: number; y: number }, player = state.currentPlayer) {
  const result = makeMove({ ...state, currentPlayer: player }, move.x, move.y);
  if (!result.valid) throw new Error(result.reason);
  return result.state;
}

function winningMoves(state: GameState, player: Player) {
  return getLegalMoves(state).filter((move) => after(state, move, player).status === 'won');
}

// Independent rules-engine oracle: a fork must survive the opponent's own wins
// and offer two distinct legal winning placements on the following turn.
function winningForks(state: GameState) {
  return getLegalMoves(state).filter((move) => {
    const next = after(state, move);
    return (
      next.status === 'playing' &&
      winningMoves(next, next.currentPlayer).length === 0 &&
      winningMoves(next, state.currentPlayer).length >= 2
    );
  });
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('bot tactics', () => {
  it.each<Difficulty>(['medium', 'hard'])(
    '%s sometimes changes a quiet opening, preserving a safe move',
    (difficulty) => {
      const state = play([[2, 2]]);
      const original = JSON.stringify(state);
      // Give both choices identical search work regardless of CPU contention.
      let clockTicks = 0;
      const tick = difficulty === 'hard' ? 650 / 300 : 180 / 120;
      vi.spyOn(performance, 'now').mockImplementation(() => clockTicks++ * tick);
      const random = vi.spyOn(Math, 'random').mockReturnValue(0.999);
      const standard = chooseMove(state, difficulty)!;
      clockTicks = 0;
      random.mockReturnValue(0);
      const alternative = chooseMove(state, difficulty)!;
      expect(alternative).not.toEqual(standard);
      expect(getLegalMoves(state)).toContainEqual(alternative);
      expect(winningMoves(after(state, alternative), 1)).toHaveLength(0);
      expect(winningForks(after(state, alternative))).toHaveLength(0);
      expect(JSON.stringify(state)).toBe(original);
    },
  );

  it.each<Difficulty>(['easy', 'medium', 'hard'])(
    '%s never randomizes away the forced defense',
    (difficulty) => {
      vi.spyOn(Math, 'random').mockReturnValue(0);
      const state = play([
        [0, 0],
        [4, 4],
        [1, 0],
        [4, 3],
        [2, 0],
      ]);
      expect(chooseMove(state, difficulty)).toEqual({ x: 3, y: 0 });
    },
  );
  it.each<Difficulty>(['easy', 'medium', 'hard'])(
    '%s takes a win before blocking',
    (difficulty) => {
      vi.spyOn(Math, 'random').mockReturnValue(0.99);
      const state = play([
        [0, 0],
        [0, 4],
        [1, 0],
        [1, 4],
        [2, 0],
        [2, 4],
      ]);
      expect(chooseMove(state, difficulty)).toEqual({ x: 3, y: 0 });
    },
  );

  it.each<Difficulty>(['easy', 'medium', 'hard'])('%s blocks an immediate loss', (difficulty) => {
    vi.spyOn(Math, 'random').mockReturnValue(0.99);
    const state = play([
      [0, 0],
      [4, 4],
      [1, 0],
      [4, 3],
      [2, 0],
    ]);
    expect(chooseMove(state, difficulty)).toEqual({ x: 3, y: 0 });
  });

  it.each<Difficulty>(['easy', 'medium', 'hard'])(
    '%s returns a legal move without mutating state',
    (difficulty) => {
      const state = play([
        [2, 2],
        [2, 2],
        [2, 2],
        [2, 2],
        [2, 2],
      ]);
      const before = JSON.stringify(state);
      const move = chooseMove(state, difficulty);
      expect(getLegalMoves(state)).toContainEqual(move);
      expect(move).not.toEqual({ x: 2, y: 2 });
      expect(JSON.stringify(state)).toBe(before);
    },
  );

  it.each<Difficulty>(['easy', 'medium', 'hard'])(
    '%s returns null for terminal games',
    (difficulty) => {
      const state = play([
        [0, 0],
        [0, 4],
        [1, 0],
        [1, 4],
        [2, 0],
        [2, 4],
        [3, 0],
      ]);
      expect(chooseMove(state, difficulty)).toBeNull();
      expect(chooseMove({ ...state, status: 'draw' }, difficulty)).toBeNull();
    },
  );

  it('returns null if every column is full', () => {
    const state = { ...createGame(), heights: Array<number>(25).fill(5) };
    expect(chooseMove(state, 'hard')).toBeNull();
  });

  it('easy can recognize a tactical win', () => {
    vi.spyOn(Math, 'random').mockReturnValue(0);
    const state = play([
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
    ]);
    expect(chooseMove(state, 'easy')).toEqual({ x: 3, y: 0 });
  });

  it.each<Difficulty>(['easy', 'medium', 'hard'])(
    '%s avoids supporting an enemy win on the next layer',
    (difficulty) => {
      const state = play([
        [0, 0],
        [1, 0],
        [4, 4],
        [0, 0],
        [2, 0],
        [1, 0],
        [4, 3],
        [2, 0],
      ]);
      expect(winningMoves(state, 2)).toHaveLength(0);
      expect(winningMoves(after(state, { x: 3, y: 0 }), 2)).toContainEqual({ x: 3, y: 0 });
      vi.spyOn(Math, 'random').mockReturnValue(0);
      const chosen = chooseMove(state, difficulty)!;
      expect(chosen).not.toEqual({ x: 3, y: 0 });
      expect(winningMoves(after(state, chosen), 2)).toHaveLength(0);
    },
  );

  it.each<Difficulty>(['medium', 'hard'])(
    '%s prevents a fork before either winning column exists',
    (difficulty) => {
      vi.spyOn(Math, 'random').mockReturnValue(0);
      const state = play([
        [4, 2],
        [2, 2],
        [2, 3],
        [0, 3],
        [1, 1],
        [4, 4],
        [0, 3],
        [2, 4],
        [3, 0],
        [3, 0],
        [4, 4],
        [0, 1],
        [2, 4],
        [0, 1],
      ]);
      expect(winningMoves(state, 1)).toHaveLength(0);
      expect(winningMoves(state, 2)).toHaveLength(0);
      // Previous medium bot chose the center, allowing this forced loss.
      expect(winningForks(after(state, { x: 2, y: 2 }))).toContainEqual({ x: 0, y: 2 });
      const chosen = chooseMove(state, difficulty)!;
      const next = after(state, chosen);
      expect(winningMoves(next, next.currentPlayer)).toHaveLength(0);
      expect(winningForks(next)).toHaveLength(0);
    },
  );

  it.each<Difficulty>(['medium', 'hard'])(
    '%s creates an unavoidable double threat',
    (difficulty) => {
      const state = play([
        [1, 2],
        [0, 0],
        [2, 2],
        [4, 4],
      ]);
      const chosen = chooseMove(state, difficulty)!;
      expect(winningForks(state)).toContainEqual(chosen);
      const next = after(state, chosen);
      for (const defense of getLegalMoves(next)) {
        const defended = after(next, defense);
        expect(defended.status).toBe('playing');
        expect(winningMoves(defended, state.currentPlayer).length).toBeGreaterThan(0);
      }
    },
  );

  it('returns a safe legal fallback when its search deadline expires immediately', () => {
    const state = play([
      [2, 2],
      [1, 1],
    ]);
    const before = JSON.stringify(state);
    let time = 0;
    vi.spyOn(performance, 'now').mockImplementation(() => (time += 1000));
    expect(getLegalMoves(state)).toContainEqual(chooseMove(state, 'hard'));
    expect(JSON.stringify(state)).toBe(before);
  });

  it.each<Difficulty>(['easy', 'medium', 'hard'])(
    '%s finds a winning diagonal across all three dimensions',
    (difficulty) => {
      const state = play([
        [0, 0],
        [1, 1],
        [1, 1],
        [2, 2],
        [2, 2],
        [3, 3],
        [2, 2],
        [3, 3],
        [3, 3],
        [4, 0],
      ]);
      const chosen = chooseMove(state, difficulty)!;
      expect(chosen).toEqual({ x: 3, y: 3 });
      const result = after(state, chosen);
      expect(result.status).toBe('won');
      expect(result.winningLines).toContainEqual([
        { x: 0, y: 0, z: 0 },
        { x: 1, y: 1, z: 1 },
        { x: 2, y: 2, z: 2 },
        { x: 3, y: 3, z: 3 },
      ]);
    },
  );
});

describe('worker lifecycle', () => {
  it('rejects an already cancelled turn', async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(requestBotMove(createGame(), 'hard', controller.signal)).rejects.toMatchObject({
      name: 'AbortError',
    });
  });

  it('terminates computation when the user leaves or restarts', async () => {
    const terminate = vi.fn();
    const postMessage = vi.fn();
    vi.stubGlobal(
      'Worker',
      class {
        terminate = terminate;
        postMessage = postMessage;
      },
    );
    const controller = new AbortController();
    const pending = requestBotMove(createGame(), 'hard', controller.signal);
    controller.abort();
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    expect(terminate).toHaveBeenCalledOnce();
    expect(postMessage).toHaveBeenCalledOnce();
  });
});
