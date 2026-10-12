import type { LobbySnapshot } from '../network/protocol';

export const RANKED_WIN_FALL_MS = 1150;
export const RANKED_WIN_LINE_MS = 700;
export const RANKED_RESULT_DELAY_MS = 3600;
export const REDUCED_RESULT_DELAY_MS = 1600;

export function hasRankedWinningLine(snapshot?: LobbySnapshot): boolean {
  return Boolean(
    snapshot?.ranking?.rated &&
    snapshot.game.status === 'won' &&
    snapshot.game.winningLines.length &&
    !snapshot.endReason,
  );
}

export function rankedResultDelay(snapshot: LobbySnapshot, animations: boolean): number {
  if (hasRankedWinningLine(snapshot))
    return animations ? RANKED_RESULT_DELAY_MS : REDUCED_RESULT_DELAY_MS;
  return snapshot.game.status === 'draw' ? 1100 : 600;
}
