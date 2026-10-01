/** Zero-sum Elo, K=32. Decisive games transfer at least one point, never below zero. */
export function ratingDelta(a: number, b: number, score: 0 | 0.5 | 1): number {
  const expected = 1 / (1 + 10 ** ((b - a) / 400));
  let delta = Math.floor(32 * (score - expected) + 0.5);
  if (score === 1) delta = Math.max(1, delta);
  if (score === 0) delta = Math.min(-1, delta);
  return Math.max(-a, Math.min(b, delta)) || 0;
}
