import { useSyncExternalStore } from 'react';

let snapshot = {
  online: typeof navigator === 'undefined' || navigator.onLine,
  ready: false,
  saving: false,
  loaded: 0,
  total: 0,
  error: false,
};
const listeners = new Set<() => void>();
let registration: ServiceWorkerRegistration | undefined;
let pending: Promise<ServiceWorkerRegistration> | undefined;
const publish = (patch: Partial<typeof snapshot>) => {
  snapshot = { ...snapshot, ...patch };
  listeners.forEach((listener) => listener());
};
export function useOffline() {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    () => snapshot,
  );
}
async function checkWorker(worker?: ServiceWorker | null) {
  if (!worker) return;
  const channel = new MessageChannel();
  const timer = setTimeout(() => channel.port1.close(), 2000);
  channel.port1.onmessage = (event) => {
    clearTimeout(timer);
    channel.port1.close();
    if (event.data?.ready) publish({ ready: true, saving: false, error: false });
    else {
      publish({ ready: false, error: true });
      retryOffline();
    }
  };
  worker.postMessage({ type: 'offline-status' }, [channel.port2]);
}
export function registerGameWorker(): Promise<ServiceWorkerRegistration> {
  if (!pending)
    pending = navigator.serviceWorker
      .register('/match-notifications.js', { updateViaCache: 'none' })
      .then((result) => {
        registration = result;
        void checkWorker(result.active);
        const watch = () => {
          const worker = result.installing;
          if (!worker) return;
          publish({ saving: import.meta.env.PROD, error: false });
          worker.addEventListener('statechange', () => {
            if (worker.state === 'installed') {
              void checkWorker(worker);
            }
            if (worker.state === 'activated') void checkWorker(worker);
            if (worker.state === 'redundant') {
              if (!result.active) {
                pending = undefined;
                registration = undefined;
              }
              publish({ saving: false, error: true });
            }
          });
        };
        result.addEventListener('updatefound', watch);
        watch();
        return result;
      })
      .catch((error) => {
        pending = undefined;
        publish({ saving: false, error: true });
        throw error;
      });
  return pending;
}
export function retryOffline() {
  if (!snapshot.online) return;
  publish({ error: false, saving: true });
  if (!snapshot.ready) registration?.active?.postMessage({ type: 'offline-prepare' });
  void (registration ? registration.update() : registerGameWorker()).catch(() =>
    publish({ saving: false, error: true }),
  );
}
export function initializeOffline() {
  window.addEventListener('online', () => {
    publish({ online: true });
    if (snapshot.error) retryOffline();
  });
  window.addEventListener('offline', () => publish({ online: false }));
  if (!import.meta.env.PROD || !window.isSecureContext || !('serviceWorker' in navigator)) return;
  navigator.serviceWorker.addEventListener('message', (event) => {
    if (event.data?.type === 'offline-progress')
      publish({ saving: true, loaded: event.data.loaded, total: event.data.total });
    if (event.data?.type === 'offline-ready') publish({ ready: true, saving: false, error: false });
    if (event.data?.type === 'offline-error') publish({ saving: false, error: true });
  });
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    void checkWorker(navigator.serviceWorker.controller);
  });
  void registerGameWorker().catch(() => {});
}
