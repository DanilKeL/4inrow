export function remainingTurnSeconds(
  deadline: number | undefined,
  pauseEndsAt: number | undefined,
  now: number,
): number | null {
  if (!deadline) return null;
  return Math.max(0, Math.ceil((deadline - (pauseEndsAt ?? now)) / 1000));
}
