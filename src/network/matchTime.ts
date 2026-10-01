import type { LobbySnapshot } from './protocol';

export function onlineElapsed(
  snapshot: Pick<LobbySnapshot, 'startedAt' | 'finishedAt' | 'pause'>,
  now = Date.now(),
): number {
  if (snapshot.startedAt === null) return 0;
  const end = snapshot.finishedAt ?? now;
  const pause = snapshot.pause;
  const activePause =
    pause?.startedAt !== undefined && pause.endsAt !== undefined
      ? Math.max(0, Math.min(end, pause.endsAt) - pause.startedAt)
      : 0;
  return Math.max(
    0,
    Math.floor((end - snapshot.startedAt - (pause?.totalMs ?? 0) - activePause) / 1000),
  );
}
