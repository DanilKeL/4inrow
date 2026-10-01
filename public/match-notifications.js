/* Notifications only: no caching, request interception or offline game state. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
self.addEventListener('message', (event) => {
  if (event.data?.type === 'notification-client') event.ports[0]?.postMessage(event.source?.id);
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
