import { afterEach, expect, it, vi } from 'vitest';
import { requestBotMove } from './index';
import { chooseMove } from './search';
import { getLevel, levelPosition, LEVEL_BOT_OPTIONS } from '../levels';
import { makeMove } from '../core';
import solutions from '../levels/solutions.json';

afterEach(() => vi.unstubAllGlobals());
it('uses the same level policy if an offline browser cannot load the worker', async () => {
  vi.stubGlobal(
    'Worker',
    class {
      onerror?: (event: { preventDefault(): void }) => void;
      terminate() {}
      postMessage() {
        queueMicrotask(() => this.onerror?.({ preventDefault() {} }));
      }
    },
  );
  const preset = levelPosition(getLevel(9)!);
  const move = solutions.find((s) => s.id === 9)!.solution[0];
  const result = makeMove(preset, move.x, move.y);
  if (!result.valid) throw new Error('Invalid fixture');
  expect(await requestBotMove(result.state, 'medium', undefined, LEVEL_BOT_OPTIONS)).toEqual(
    chooseMove(result.state, 'medium', LEVEL_BOT_OPTIONS),
  );
});
