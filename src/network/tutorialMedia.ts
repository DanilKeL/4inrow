import { tutorialExamples } from '../ui/tutorialExamples';

const urls = new Map<string, string>();
const listeners = new Set<() => void>();
let snapshot = { loaded: 0, completed: 0, total: tutorialExamples.length, ready: false };
let pending: Promise<void> | undefined;

export const tutorialMediaSnapshot = () => snapshot;
export function subscribeTutorialMedia(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
export const tutorialVideoUrl = (id: string) => urls.get(id) ?? `/tutorial/${id}.mp4`;

/** Fetch complete files once; blob URLs also avoid a second range download by <video>. */
export function preloadTutorialMedia(): Promise<void> {
  if (pending) return pending;
  pending = (async () => {
    let next = 0;
    async function worker() {
      while (next < tutorialExamples.length) {
        const { id } = tutorialExamples[next++];
        const path = `/tutorial/${id}.mp4`;
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 30000);
        try {
          // The versioned game worker owns disk caching; avoid stale parallel caches.
          const response = await fetch(path, { signal: controller.signal, cache: 'no-cache' });
          if (!response.ok) throw new Error('Tutorial video unavailable');
          const blob = await response.blob();
          if (!blob.size || !blob.type.startsWith('video/'))
            throw new Error('Invalid tutorial video');
          urls.set(id, URL.createObjectURL(blob));
          snapshot = { ...snapshot, loaded: snapshot.loaded + 1 };
        } catch {
          // Rules retain their poster and can try streaming the original URL later.
        } finally {
          clearTimeout(timeout);
          snapshot = { ...snapshot, completed: snapshot.completed + 1 };
          listeners.forEach((listener) => listener());
        }
      }
    }
    // Leave bandwidth available for the board and fonts during startup.
    await Promise.all([worker(), worker()]);
    snapshot = { ...snapshot, ready: true };
    listeners.forEach((listener) => listener());
  })();
  return pending;
}
