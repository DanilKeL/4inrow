// Replaced by the production build. Development retains notifications only.
const OFFLINE_BUILD = null;
const CACHE_PREFIX = 'four-offline-';
const CACHE_NAME = OFFLINE_BUILD ? CACHE_PREFIX + OFFLINE_BUILD.version : null;
const READY_KEY = '/__four_offline_ready__';
const assets = new Set(OFFLINE_BUILD?.entries.map((entry) => entry.url) ?? []);
let progress = { loaded: 0, total: OFFLINE_BUILD?.entries.length ?? 0 };
let preparation;
function prepareGame() {
  if (!preparation)
    preparation = installGame()
      .catch(async (error) => {
        await broadcast({ type: 'offline-error', reason: String(error) });
        throw error;
      })
      .finally(() => {
        preparation = undefined;
      });
  return preparation;
}
async function broadcast(data) {
  for (const client of await self.clients.matchAll({ includeUncontrolled: true }))
    client.postMessage(data);
}
async function matchesHash(response, hash) {
  if (!response?.ok || response.status !== 200) return false;
  const digest = await crypto.subtle.digest('SHA-256', await response.clone().arrayBuffer());
  return (
    Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('') ===
    hash
  );
}
async function installGame() {
  progress = { loaded: 0, total: OFFLINE_BUILD.entries.length };
  const cache = await caches.open(CACHE_NAME);
  const oldCaches = await Promise.all(
    (await caches.keys())
      .filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME)
      .map((name) => caches.open(name)),
  );
  let next = 0;
  try {
    async function download() {
      while (next < OFFLINE_BUILD.entries.length) {
        const entry = OFFLINE_BUILD.entries[next++];
        let response = await cache.match(entry.url);
        if (!(await matchesHash(response, entry.hash))) {
          response = undefined;
          for (const old of oldCaches) {
            const candidate = await old.match(entry.url);
            if (await matchesHash(candidate, entry.hash)) {
              response = candidate;
              break;
            }
          }
          if (!response)
            response = await fetch(`${entry.url}?__four_precache=${OFFLINE_BUILD.version}`, {
              cache: 'reload',
              signal: AbortSignal.timeout(60000),
            });
          if (!(await matchesHash(response, entry.hash)))
            throw new Error(`Offline file unavailable: ${entry.url}`);
          await cache.put(entry.url, response);
        }
        progress = { ...progress, loaded: progress.loaded + 1 };
        await broadcast({ type: 'offline-progress', ...progress });
      }
    }
    await Promise.all([download(), download()]);
    await cache.put(READY_KEY, new Response(JSON.stringify({ version: OFFLINE_BUILD.version })));
    await broadcast({ type: 'offline-ready', version: OFFLINE_BUILD.version });
    // Upgrade the old notifications-only worker without interrupting gameplay.
    // Subsequent game updates wait until all tabs close or the player accepts them.
    if (!oldCaches.length) await self.skipWaiting();
  } catch (error) {
    if (!(await cache.match(READY_KEY))) await caches.delete(CACHE_NAME);
    await broadcast({ type: 'offline-error' });
    throw error;
  }
}
self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const hasPreviousGame =
        OFFLINE_BUILD &&
        (await caches.keys()).some((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME);
      // Initial notification delivery must not wait for an offline download.
      // The activated page prepares its cache; game updates install atomically.
      if (hasPreviousGame) await prepareGame();
      else await self.skipWaiting();
    })(),
  );
});
self.addEventListener('activate', (event) =>
  event.waitUntil(
    (async () => {
      if (OFFLINE_BUILD) {
        const previous = (await caches.keys()).filter(
          (name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME,
        );
        // Retain the previous build for any other open tab accepting an update later.
        await Promise.all(previous.slice(0, -1).map((name) => caches.delete(name)));
      }
      await self.clients.claim();
    })(),
  ),
);
async function cachedResponse(request, path) {
  const cache = await caches.open(CACHE_NAME);
  let response = await cache.match(path);
  if (!response && path.startsWith('/assets/')) {
    // An existing tab can still request a lazy chunk from the previous build.
    for (const name of await caches.keys()) {
      if (!name.startsWith(CACHE_PREFIX)) continue;
      response = await (await caches.open(name)).match(path);
      if (response) break;
    }
  }
  if (!response) return fetch(request);
  const range = request.headers.get('range');
  if (!range) return response;
  const bytes = await response.arrayBuffer();
  const parts = /^bytes=(\d*)-(\d*)$/.exec(range);
  if (!parts || (!parts[1] && !parts[2]))
    return new Response(null, {
      status: 416,
      headers: { 'Content-Range': `bytes */${bytes.byteLength}` },
    });
  const start = parts[1] ? Number(parts[1]) : Math.max(0, bytes.byteLength - Number(parts[2]));
  const end =
    parts[1] && parts[2] ? Math.min(Number(parts[2]), bytes.byteLength - 1) : bytes.byteLength - 1;
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(end) ||
    start > end ||
    start >= bytes.byteLength
  )
    return new Response(null, {
      status: 416,
      headers: { 'Content-Range': `bytes */${bytes.byteLength}` },
    });
  const headers = new Headers(response.headers);
  headers.set('Content-Range', `bytes ${start}-${end}/${bytes.byteLength}`);
  headers.set('Content-Length', String(end - start + 1));
  headers.delete('Content-Encoding');
  headers.set('Accept-Ranges', 'bytes');
  return new Response(bytes.slice(start, end + 1), { status: 206, headers });
}
self.addEventListener('fetch', (event) => {
  if (!OFFLINE_BUILD || event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  if (url.searchParams.has('__four_precache')) return;
  // Auth, admin, telemetry, health and all API responses are never cached.
  if (
    event.request.mode === 'navigate' &&
    (url.pathname === '/' || url.pathname.startsWith('/room/'))
  ) {
    event.respondWith(cachedResponse(event.request, '/').catch(() => fetch(event.request)));
  } else if (assets.has(url.pathname) || url.pathname.startsWith('/assets/')) {
    event.respondWith(cachedResponse(event.request, url.pathname).catch(() => fetch(event.request)));
  }
});
self.addEventListener('message', (event) => {
  if (event.data?.type === 'notification-client') event.ports[0]?.postMessage(event.source?.id);
  if (event.data?.type === 'offline-status' && OFFLINE_BUILD)
    event.waitUntil(
      (async () => {
        let ready = false;
        try {
          const cache = await caches.open(CACHE_NAME);
          const paths = new Set(
            (await cache.keys()).map((request) => new URL(request.url).pathname),
          );
          ready =
            Boolean(await cache.match(READY_KEY)) &&
            OFFLINE_BUILD.entries.every((entry) => paths.has(entry.url));
        } catch {
          /* Notifications still work when cache storage is restricted. */
        }
        event.ports[0]?.postMessage({ ready, version: OFFLINE_BUILD.version, ...progress });
      })(),
    );
  if (event.data?.type === 'offline-activate') event.waitUntil(self.skipWaiting());
  if (event.data?.type === 'offline-prepare' && OFFLINE_BUILD) event.waitUntil(prepareGame());
});
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const pages = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const page =
        pages.find((client) => client.id === event.notification.data?.clientId) ??
        pages.find((client) => new URL(client.url).origin === self.location.origin);
      if (page) await page.focus();
    })(),
  );
});
