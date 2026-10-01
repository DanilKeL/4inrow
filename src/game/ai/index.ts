import type { GameState } from '../core';
import { chooseMove, type Difficulty, type MoveCandidate, type BotOptions } from './search';

export { chooseMove, type Difficulty, type MoveCandidate } from './search';

/** One worker per turn: cancelling a turn immediately stops its computation. */
export function requestBotMove(
  state: GameState,
  difficulty: Difficulty,
  signal?: AbortSignal,
  options: BotOptions = {},
): Promise<MoveCandidate | null> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException('Bot turn cancelled', 'AbortError'));
      return;
    }
    if (state.status !== 'playing') {
      resolve(null);
      return;
    }

    let worker: Worker | undefined;
    let fallbackTimer: ReturnType<typeof setTimeout> | undefined;
    const cleanup = () => {
      worker?.terminate();
      clearTimeout(fallbackTimer);
      signal?.removeEventListener('abort', abort);
    };
    const abort = () => {
      cleanup();
      reject(new DOMException('Bot turn cancelled', 'AbortError'));
    };
    signal?.addEventListener('abort', abort, { once: true });

    const fallback = () => {
      worker?.terminate();
      worker = undefined;
      fallbackTimer = setTimeout(() => {
        try {
          resolve(chooseMove(state, difficulty, options));
        } catch (error) {
          reject(error);
        } finally {
          cleanup();
        }
      }, 0);
    };
    // Levels remain playable if an offline browser cannot load the worker chunk.
    if (typeof Worker === 'undefined') {
      fallback();
      return;
    }
    try {
      worker = new Worker(new URL('./bot.worker.ts', import.meta.url), { type: 'module' });
      worker.onmessage = (event: MessageEvent<MoveCandidate | null>) => {
        cleanup();
        resolve(event.data);
      };
      worker.onerror = (event) => {
        if (options.deterministic) {
          event.preventDefault();
          fallback();
          return;
        }
        cleanup();
        reject(new Error(event.message || 'The bot worker could not start'));
      };
      worker.postMessage({ state, difficulty, options });
    } catch (error) {
      if (options.deterministic) {
        fallback();
        return;
      }
      cleanup();
      reject(error);
    }
  });
}
