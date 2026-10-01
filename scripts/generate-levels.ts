import { createGame, makeMove, getLegalMoves, type GameState } from '../src/game/core/index';
import { chooseMove } from '../src/game/ai/search';
import { mkdirSync, writeFileSync } from 'node:fs';

// Build-time only. Commit the resulting positions and their reproducible winning lines.
let seed = 0x4c455645;
function random() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 4294967296;
}
type Point = { x: number; y: number };
const pools: { preset: Point[]; solution: Point[]; pieces: number; height: number }[][] =
  Array.from({ length: 5 }, () => []);
const seen = new Set<string>();
function canonical(state: GameState) {
  const variants: string[] = [];
  for (let flip = 0; flip < 2; flip++)
    for (let rot = 0; rot < 4; rot++) {
      const cells = Array(125).fill(0);
      for (let z = 0; z < 5; z++)
        for (let y = 0; y < 5; y++)
          for (let x = 0; x < 5; x++) {
            let a = flip ? 4 - x : x,
              b = y;
            for (let i = 0; i < rot; i++) [a, b] = [4 - b, a];
            cells[a + b * 5 + z * 25] = state.board[x + y * 5 + z * 25];
          }
      variants.push(cells.join(''));
    }
  return variants.sort()[0];
}
for (let attempt = 0; attempt < 2500 && pools.some((p) => p.length < 8); attempt++) {
  let start = createGame();
  const count = 10 + Math.floor(random() * 22) * 2;
  for (let i = 0; i < count; i++) {
    const legal = getLegalMoves(start).filter((p) => {
      const r = makeMove(start, p.x, p.y);
      return r.valid && r.state.status === 'playing';
    });
    if (!legal.length) break;
    const p = legal[Math.floor(random() * legal.length)];
    const r = makeMove(start, p.x, p.y);
    if (r.valid) start = r.state;
  }
  if (start.currentPlayer !== 1 || start.history.length < 10) continue;
  const key = canonical(start);
  if (seen.has(key)) continue;
  let state = start;
  const solution: Point[] = [];
  for (let ply = 0; ply < 20 && state.status === 'playing'; ply++) {
    const player = state.currentPlayer;
    const p = chooseMove(state, player === 1 ? 'hard' : 'medium', {
      deterministic: true,
      nodeBudget: player === 1 ? 16000 : 6000,
    });
    if (!p) break;
    const r = makeMove(state, p.x, p.y);
    if (!r.valid) throw new Error('Invalid bot move');
    if (player === 1) solution.push(p);
    state = r.state;
  }
  if (state.winner !== 1) continue;
  const n = solution.length;
  const group = n <= 2 ? 0 : n === 3 ? 1 : n === 4 ? 2 : n <= 6 ? 3 : 4;
  if (
    pools[group].length >= 8 ||
    (group === 0 && n === 1 && pools[0].filter((p) => p.solution.length === 1).length >= 3)
  )
    continue;
  seen.add(key);
  pools[group].push({
    preset: start.history.map(({ x, y }) => ({ x, y })),
    solution,
    pieces: start.history.length,
    height: Math.max(...start.heights),
  });
  console.log(
    `Position ${pools.flat().length}: ${n} moves, ${start.history.length} pieces. Groups ${pools.map((p) => p.length).join('/')}`,
  );
}
if (pools.some((p) => p.length < 8))
  throw new Error(`Insufficient positions: ${pools.map((p) => p.length)}`);
const labels = ['Первые решения', 'Тактика', 'Комбинации', 'Контратака', 'Сложные позиции'];
const data = pools.flatMap((p, group) =>
  p
    .sort((a, b) => a.solution.length - b.solution.length)
    .map((entry, i) => ({
      id: group * 8 + i + 1,
      chapter: labels[group],
      preset: entry.preset,
      solution: entry.solution,
    })),
);
mkdirSync('src/game/levels', { recursive: true });
writeFileSync(
  'src/game/levels/levels.json',
  JSON.stringify(
    data.map(({ id, chapter, preset }) => ({ id, chapter, preset })),
    null,
    2,
  ) + '\n',
);
writeFileSync(
  'src/game/levels/solutions.json',
  JSON.stringify(
    data.map(({ id, solution }) => ({ id, solution })),
    null,
    2,
  ) + '\n',
);
console.log('Saved 40 validated level candidates.');
