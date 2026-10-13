import { WIN_CAMERA_MS, WIN_FALL_MS, WIN_LINE_MS } from '../game/victoryPresentation';

const clamp = (value: number) => Math.max(0, Math.min(1, value));
const smooth = (value: number) => value * value * (3 - 2 * value);

/** The entire board shares one clock so rings never precede the final chip. */
export function rankedVictoryProgress(elapsedMs: number) {
  const fall = clamp((elapsedMs - WIN_CAMERA_MS) / WIN_FALL_MS);
  const reveal = clamp((elapsedMs - WIN_CAMERA_MS - WIN_FALL_MS) / WIN_LINE_MS);
  return {
    fallOffset: 2.2 * (1 - fall * fall),
    lineProgress: smooth(reveal),
    dimProgress: smooth(reveal),
    ringProgress: smooth(clamp((elapsedMs - WIN_CAMERA_MS - WIN_FALL_MS) / 320)),
  };
}

/** Each segment occupies its own part of the continuous line reveal. */
export function rankedSegmentProgress(progress: number, segment: number, total: number) {
  return clamp(progress * total - segment);
}

export interface RankedVictoryClock {
  key: string;
  startedAt: number;
}
