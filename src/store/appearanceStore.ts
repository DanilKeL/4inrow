import { create } from 'zustand';
import { defaultCatalog, isCatalog, type SkinCatalog } from '../skins/catalog';

const CACHE_KEY = 'four-skins-v1';
function cachedCatalog(): SkinCatalog {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(CACHE_KEY) ?? 'null');
    if (isCatalog(saved)) return saved;
  } catch {
    /* Offline play does not depend on storage. */
  }
  return defaultCatalog();
}
export const useAppearance = create<{
  catalog: SkinCatalog;
  setCatalog: (value: unknown) => void;
}>((set, get) => ({
  catalog: cachedCatalog(),
  setCatalog: (value) => {
    if (!isCatalog(value)) return;
    const unchanged = JSON.stringify(get().catalog) === JSON.stringify(value);
    try {
      localStorage.setItem(CACHE_KEY, JSON.stringify(value));
    } catch {
      /* Optional cache. */
    }
    if (!unchanged) set({ catalog: value });
  },
}));

export function initializeAppearance(): () => void {
  let stopped = false;
  let generation = 0;
  let source: EventSource | undefined;
  let controller: AbortController | undefined;
  const disconnect = () => {
    generation++;
    source?.close();
    source = undefined;
    controller?.abort();
  };
  const connect = async () => {
    disconnect();
    if (stopped || document.hidden || !navigator.onLine) return;
    const current = generation;
    controller = new AbortController();
    try {
      const response = await fetch('/appearance', {
        cache: 'no-store',
        signal: AbortSignal.any([controller.signal, AbortSignal.timeout(5000)]),
      });
      if (response.ok) {
        const catalog: unknown = await response.json();
        if (!stopped && generation === current) useAppearance.getState().setCatalog(catalog);
      }
    } catch {
      /* Retain the last style when offline. */
    }
    if (stopped || generation !== current || typeof EventSource === 'undefined') return;
    source = new EventSource('/appearance/events');
    source.addEventListener('skins', (event) => {
      if (stopped || generation !== current) return;
      try {
        useAppearance.getState().setCatalog(JSON.parse(event.data));
      } catch {
        /* Ignore malformed events. */
      }
    });
  };
  const visibility = () => {
    if (document.hidden) disconnect();
    else void connect();
  };
  window.addEventListener('online', visibility);
  window.addEventListener('offline', disconnect);
  window.addEventListener('pageshow', visibility);
  document.addEventListener('visibilitychange', visibility);
  const timer = window.setInterval(() => {
    if (!source || source.readyState !== EventSource.OPEN) void connect();
  }, 30000);
  void connect();
  return () => {
    stopped = true;
    disconnect();
    window.clearInterval(timer);
    window.removeEventListener('online', visibility);
    window.removeEventListener('offline', disconnect);
    window.removeEventListener('pageshow', visibility);
    document.removeEventListener('visibilitychange', visibility);
  };
}
