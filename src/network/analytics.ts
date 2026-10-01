import { serialize } from '../game/core';
import { useGame } from '../store/gameStore';
import { useAccount } from '../store/accountStore';

type Event = Record<string, unknown>;
type Session = { id: string; lastSeen: number; activeSeconds: number };
const QUEUE_KEY = 'four-analytics-outbox-v1';
let initialized = false;
let identityReady = false;
let visitor = '';
let session: Session;
let queue: Event[] = [];
let sending = false;
let heartbeatAt = Date.now();
let currentGame: { id: string; elapsed: number; finished: boolean } | null = null;

const read = <T>(key: string, fallback: T): T => {
  try {
    return (JSON.parse(localStorage.getItem(key) ?? 'null') as T) ?? fallback;
  } catch {
    return fallback;
  }
};
function persist() {
  try {
    localStorage.setItem(QUEUE_KEY, JSON.stringify(queue));
  } catch {
    /* Memory still works. */
  }
}
function enqueue(event: Event) {
  if (event.type === 'heartbeat') {
    const index = queue.findIndex(
      (e, i) => !(sending && i === 0) && e.type === 'heartbeat' && e.session === session.id,
    );
    if (index >= 0) queue.splice(index, 1);
  }
  queue.push({
    ...event,
    visitor,
    session: session.id,
    occurredAt: Date.now(),
    owner: useAccount.getState().username,
  });
  if (queue.length > 150) {
    const heartbeatIndex = queue.findIndex(
      (e, i) => !(sending && i === 0) && e.type === 'heartbeat',
    );
    if (heartbeatIndex >= 0) queue.splice(heartbeatIndex, 1);
    else queue = queue.slice(-150);
  }
  persist();
  void flush();
}
async function flush() {
  if (sending || !initialized || !identityReady || !navigator.onLine) return;
  sending = true;
  try {
    while (queue.length) {
      const event = queue[0];
      const response = await fetch('/telemetry', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(event),
        signal: AbortSignal.timeout(8000),
        keepalive: true,
      });
      if (!response.ok && (response.status >= 500 || response.status === 429)) break;
      // Invalid old events must not block later visits indefinitely.
      queue.shift();
      persist();
    }
  } catch {
    /* Retry on the next heartbeat or reconnect. */
  } finally {
    sending = false;
  }
}
function visit() {
  const ua = navigator.userAgent;
  const device =
    /iPad|Tablet/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)
      ? 'tablet'
      : /Mobi|Android|iPhone/i.test(ua)
        ? 'mobile'
        : 'desktop';
  const browser = /YaBrowser/i.test(ua)
    ? 'Yandex'
    : /SamsungBrowser/i.test(ua)
      ? 'Samsung'
      : /Edg/i.test(ua)
        ? 'Edge'
        : /Firefox|FxiOS/i.test(ua)
          ? 'Firefox'
          : /Chrome|CriOS/i.test(ua)
            ? 'Chrome'
            : /Safari/i.test(ua)
              ? 'Safari'
              : 'Other';
  enqueue({ type: 'visit', device, browser, referrer: document.referrer });
}
function heartbeat(visible = document.visibilityState === 'visible') {
  const now = Date.now();
  if (visible) {
    session.activeSeconds += Math.max(0, Math.min(60, Math.floor((now - heartbeatAt) / 1000)));
    session.lastSeen = now;
    try {
      sessionStorage.setItem('four-analytics-session', JSON.stringify(session));
    } catch {
      /* Memory fallback. */
    }
    enqueue({ type: 'heartbeat', activeSeconds: session.activeSeconds });
  }
  heartbeatAt = now;
}
export function initializeAnalytics() {
  if (initialized || typeof window === 'undefined') return;
  initialized = true;
  visitor = read<string>('four-analytics-visitor', '');
  if (typeof visitor !== 'string' || !/^[a-zA-Z0-9-]{8,140}$/.test(visitor)) visitor = identifier();
  try {
    localStorage.setItem('four-analytics-visitor', JSON.stringify(visitor));
  } catch {
    /* Memory fallback. */
  }
  let saved: Session | null = null;
  try {
    saved = JSON.parse(
      sessionStorage.getItem('four-analytics-session') ?? 'null',
    ) as Session | null;
  } catch {
    /* New visit. */
  }
  session =
    saved &&
    typeof saved.id === 'string' &&
    /^[a-zA-Z0-9-]{8,140}$/.test(saved.id) &&
    Date.now() - saved.lastSeen < 30 * 60_000 &&
    Number.isFinite(saved.activeSeconds)
      ? saved
      : { id: identifier(), lastSeen: Date.now(), activeSeconds: 0 };
  try {
    sessionStorage.setItem('four-analytics-session', JSON.stringify(session));
  } catch {
    /* Memory fallback. */
  }
  const stored = read<unknown>(QUEUE_KEY, []);
  queue = Array.isArray(stored)
    ? (stored.filter((e) => e && typeof e === 'object').slice(-150) as Event[])
    : [];
  // Delay initial submission until the site's identity cookie has been established.
  void useAccount
    .getState()
    .load()
    .finally(() => {
      identityReady = true;
      // The initial visit must precede games started while identity was loading.
      const waiting = queue.splice(0);
      visit();
      queue.push(...waiting);
      persist();
      void flush();
    });
  window.setInterval(() => heartbeat(), 30_000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') heartbeat(true);
    else {
      heartbeatAt = Date.now();
      if (Date.now() - session.lastSeen > 30 * 60_000 && !currentGame) {
        session = { id: identifier(), lastSeen: Date.now(), activeSeconds: 0 };
        visit();
      } else visit();
    }
  });
  window.addEventListener('online', () => void flush());
  window.addEventListener('pagehide', () => {
    heartbeat();
    // Keep the ordered durable outbox; mobile backgrounding is not leaving a match.
  });
  useAccount.subscribe((state, previous) => {
    if (identityReady && state.username !== previous.username) visit();
  });
  let pending = false;
  useGame.subscribe(() => {
    if (pending) return;
    pending = true;
    queueMicrotask(() => {
      pending = false;
      const state = useGame.getState();
      const local =
        ['ai', 'local', 'level'].includes(state.mode) &&
        !state.archiveId &&
        state.phase !== 'menu' &&
        !!state.recordId;
      if (currentGame && (!local || state.recordId !== currentGame.id)) {
        if (!currentGame.finished)
          enqueue({ type: 'game_abandon', id: currentGame.id, elapsed: currentGame.elapsed });
        currentGame = null;
      }
      if (!local) return;
      if (!currentGame) {
        currentGame = { id: state.recordId, elapsed: state.elapsed, finished: false };
        enqueue({
          type: 'game_start',
          id: state.recordId,
          mode: state.mode,
          difficulty: state.difficulty,
          level: state.levelId,
        });
      }
      currentGame.elapsed = state.elapsed;
      if (state.game.status !== 'playing' && !currentGame.finished) {
        currentGame.finished = true;
        enqueue({
          type: 'game_end',
          id: state.recordId,
          game: serialize(state.game),
          elapsed: state.elapsed,
        });
      }
    });
  });
}
function identifier() {
  return Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) =>
    b.toString(16).padStart(2, '0'),
  ).join('');
}
