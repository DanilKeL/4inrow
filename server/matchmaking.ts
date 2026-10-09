export interface MatchCandidate<T> {
  id: T;
  account: string | null;
  rating: number | null;
  queuedAt: number;
  order: number;
}

export function ratingSearchRange(waitedMs: number): number {
  if (waitedMs >= 30_000) return Infinity;
  return 100 + Math.floor(Math.max(0, waitedMs) / 3000) * 100;
}

/** Oldest searches have priority; choose their closest mutually eligible opponent. */
export function waitingPairs<T>(
  candidates: MatchCandidate<T>[],
  now: number,
  limit: number,
): [T, T][] {
  const ordered = [...candidates].sort((a, b) => a.queuedAt - b.queuedAt || a.order - b.order);
  const available = new Set(ordered.map((candidate) => candidate.id));
  const pairs: [T, T][] = [];
  for (const first of ordered) {
    if (pairs.length >= limit) break;
    if (!available.has(first.id)) continue;
    let closest: MatchCandidate<T> | undefined;
    let closestGap = Infinity;
    for (const other of ordered) {
      if (
        first.id === other.id ||
        !available.has(other.id) ||
        Boolean(first.account) !== Boolean(other.account) ||
        (first.account && first.account === other.account)
      )
        continue;
      const gap = first.account ? Math.abs(first.rating! - other.rating!) : 0;
      const range = Math.min(
        ratingSearchRange(now - first.queuedAt),
        ratingSearchRange(now - other.queuedAt),
      );
      if (first.account && gap > range) continue;
      if (gap < closestGap) {
        closest = other;
        closestGap = gap;
      }
    }
    if (!closest) continue;
    available.delete(first.id);
    available.delete(closest.id);
    pairs.push([first.id, closest.id]);
  }
  return pairs;
}
