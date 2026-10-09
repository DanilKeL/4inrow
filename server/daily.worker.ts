import { parentPort } from 'node:worker_threads';
import { generateDailyChallenge } from './dailyGenerator.ts';
import { verifyDailyResult, type DailyMove } from './dailyReplay.ts';
import type { DailyChallenge } from '../src/game/daily.ts';

type Task =
  | { type: 'generate'; date: string }
  | { type: 'verify'; challenge: DailyChallenge; moves: DailyMove[] };

parentPort?.on('message', async (task: Task) => {
  try {
    const value =
      task.type === 'generate'
        ? (await generateDailyChallenge(task.date)).challenge
        : verifyDailyResult(task.challenge, task.moves);
    parentPort?.postMessage({ ok: true, value });
  } catch (error) {
    parentPort?.postMessage({
      ok: false,
      error: error instanceof Error ? error.message : 'Daily computation failed',
    });
  }
});
