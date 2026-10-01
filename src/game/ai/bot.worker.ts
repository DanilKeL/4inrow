import type { GameState } from '../core';
import { chooseMove, type Difficulty, type BotOptions } from './search';

self.onmessage = (
  event: MessageEvent<{ state: GameState; difficulty: Difficulty; options?: BotOptions }>,
) => {
  self.postMessage(chooseMove(event.data.state, event.data.difficulty, event.data.options));
};
