import { playSound, unlockAudio } from '../audio/sound';
import { useSettings } from '../store/settingsStore';
import { registerGameWorker } from './offline';

let worker: Promise<ServiceWorkerRegistration | undefined> | undefined;
let current: string | null = null;
let notification: Notification | undefined;
let timeout: ReturnType<typeof setTimeout> | undefined;
let title: string | undefined;
let permissionRequest: Promise<NotificationPermission> | undefined;
let deliveryFailed = false;
const listeners = new Set<() => void>();
const publish = () => listeners.forEach((listener) => listener());
export function subscribeMatchAlerts(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
export function matchAlertStatus() {
  if (!window.isSecureContext) return 'insecure';
  const ios =
    /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone =
    window.matchMedia?.('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone;
  if (ios && !standalone) return 'home-screen';
  if (typeof Notification === 'undefined') return 'unsupported';
  if (permissionRequest) return 'prompting';
  if (Notification.permission === 'denied') return 'denied';
  if (deliveryFailed) return 'failed';
  return Notification.permission;
}
export function refreshMatchAlerts() {
  publish();
}

function prepareWorker() {
  if (!window.isSecureContext || !('serviceWorker' in navigator)) return undefined;
  if (!worker) {
    worker = (async () => {
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        // Bound activation as well as registration; never wait forever on a failed worker.
        return await Promise.race([
          registerGameWorker().then(() => navigator.serviceWorker.ready),
          new Promise<never>((_, reject) => {
            timer = setTimeout(() => reject(new Error('Notification worker timed out')), 10000);
          }),
        ]);
      } catch {
        worker = undefined; // A later search or explicit retry can register again.
        deliveryFailed = true;
        publish();
        return undefined;
      } finally {
        clearTimeout(timer);
      }
    })();
  }
  return worker;
}
const alertTag = `four-match-${Math.random().toString(36).slice(2)}`;
async function notificationClient(registration: ServiceWorkerRegistration) {
  if (!registration.active) return undefined;
  return new Promise<string | undefined>((resolve) => {
    const channel = new MessageChannel();
    const finish = (id?: string) => {
      clearTimeout(timer);
      channel.port1.close();
      resolve(id);
    };
    const timer = setTimeout(() => finish(), 500);
    channel.port1.onmessage = (event) =>
      finish(typeof event.data === 'string' ? event.data : undefined);
    registration.active!.postMessage({ type: 'notification-client' }, [channel.port2]);
  });
}
export function prepareMatchAlerts() {
  try {
    unlockAudio();
  } catch {
    /* The confirmation dialog still works without audio. */
  }
  if (typeof Notification === 'undefined' || !window.isSecureContext) return;
  deliveryFailed = false;
  // Keep the request in the tap handler, but wait for its result if a match arrives first.
  if (Notification.permission === 'default' && !permissionRequest) {
    try {
      permissionRequest = Notification.requestPermission()
        .catch(() => Notification.permission)
        .finally(() => {
          permissionRequest = undefined;
          publish();
        });
    } catch {
      deliveryFailed = true;
    }
  }
  prepareWorker();
  publish();
}
export function clearMatchAlert() {
  current = null;
  clearTimeout(timeout);
  notification?.close();
  notification = undefined;
  if (title !== undefined) {
    document.title = title;
    title = undefined;
  }
  if (worker)
    void worker
      .then(async (registration) => {
        for (const item of (await registration?.getNotifications({ tag: alertTag })) ?? [])
          if (item.data?.matchId !== current) item.close();
      })
      .catch(() => {});
}
export function notifyMatchFound(id: string, opponent: string, deadline: number) {
  if (current === id || deadline <= Date.now()) return;
  clearMatchAlert();
  current = id;
  title = document.title;
  document.title = 'Соперник найден! — FOUR³';
  playSound('match');
  timeout = setTimeout(clearMatchAlert, Math.max(0, deadline - Date.now()));
  if (typeof Notification === 'undefined' || !window.isSecureContext) return;
  const { sound, volume } = useSettings.getState();
  const options: NotificationOptions = {
    body: `${opponent} ждёт вас. Подтвердите матч в игре за 15 секунд.`,
    tag: alertTag,
    icon: '/icons/icon-192.png',
    silent: !sound || volume === 0,
    data: { matchId: id, deadline },
  };
  void (async () => {
    const permission = permissionRequest ? await permissionRequest : Notification.permission;
    if (permission !== 'granted' || current !== id || Date.now() >= deadline) return;
    const registration = await prepareWorker();
    if (current !== id || Date.now() >= deadline) return;
    if (registration) {
      options.data.clientId = await notificationClient(registration);
      if (current !== id || Date.now() >= deadline) return;
      await registration.showNotification('Соперник найден', options);
      if (current !== id)
        for (const item of await registration.getNotifications({ tag: alertTag }))
          if (item.data?.matchId === id) item.close();
    } else {
      notification = new Notification('Соперник найден', options);
      notification.onclick = () => {
        window.focus();
        clearMatchAlert();
      };
    }
  })().catch(() => {
    if (current === id) {
      deliveryFailed = true;
      publish();
    }
  });
}
