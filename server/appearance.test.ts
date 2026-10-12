import { afterEach, expect, it } from 'vitest';
import type { AddressInfo } from 'node:net';
import { createOnlineServer } from './app';
import { createAdminPasswordHash } from './admin';
import { BUILTIN_SKINS, defaultCatalog, type SkinCatalog } from '../src/skins/catalog';

let app: ReturnType<typeof createOnlineServer>;
let url: string;
const streams: AbortController[] = [];
afterEach(async () => {
  streams.splice(0).forEach((stream) => stream.abort());
  await app?.close();
});
async function start() {
  app = createOnlineServer({
    staticDir: null,
    authFile: null,
    statsFile: null,
    telegram: null,
    adminPasswordHash: await createAdminPasswordHash('skin-control-test-123'),
  });
  await new Promise<void>((resolve) => app.httpServer.listen(0, '127.0.0.1', resolve));
  url = `http://127.0.0.1:${(app.httpServer.address() as AddressInfo).port}`;
  const login = await fetch(url + '/admin-api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'admin', password: 'skin-control-test-123' }),
  });
  return login.headers.getSetCookie()[0].split(';')[0];
}
it('allows public reads but restricts every editor operation to the administrator and same origin', async () => {
  const cookie = await start();
  expect((await fetch(url + '/appearance').then((r) => r.json())).activeSkinId).toBe(
    'coffee-board',
  );
  for (const [method, path] of [
    ['GET', '/admin-api/skins'],
    ['POST', '/admin-api/skins'],
    ['PATCH', '/admin-api/skins'],
    ['PATCH', '/admin-api/skins/classic'],
    ['DELETE', '/admin-api/skins/classic'],
  ]) {
    expect((await fetch(url + path, { method })).status).toBe(401);
  }
  expect(
    (
      await fetch(url + '/admin-api/skins', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Cookie: cookie,
          Origin: 'https://other.example',
        },
        body: JSON.stringify({ activeSkinId: 'classic', expectedRevision: 0 }),
      })
    ).status,
  ).toBe(403);
  expect((await fetch(url + '/appearance', { method: 'POST' })).status).toBe(405);
});
it('broadcasts a saved and activated custom style immediately to independent open streams', async () => {
  const cookie = await start();
  async function subscribe() {
    const controller = new AbortController();
    streams.push(controller);
    const response = await fetch(url + '/appearance/events', { signal: controller.signal });
    expect(response.headers.get('x-accel-buffering')).toBe('no');
    const reader = response.body!.getReader();
    let buffer = '';
    return async (): Promise<SkinCatalog> => {
      for (;;) {
        const split = buffer.indexOf('\n\n');
        if (split >= 0) {
          const chunk = buffer.slice(0, split);
          buffer = buffer.slice(split + 2);
          if (chunk.startsWith('event: skins'))
            return JSON.parse(chunk.split('data: ')[1]) as SkinCatalog;
          continue;
        }
        const chunk = await reader.read();
        if (chunk.done) throw new Error('Appearance stream closed');
        buffer += new TextDecoder().decode(chunk.value);
      }
    };
  }
  const a = await subscribe(),
    b = await subscribe();
  expect((await a()).revision).toBe(0);
  await b();
  const headers = { 'Content-Type': 'application/json', Cookie: cookie };
  const saved = await fetch(url + '/admin-api/skins', {
    method: 'POST',
    headers,
    body: JSON.stringify({
      name: 'Мокко',
      palette: defaultCatalog().skins[1].palette,
      expectedRevision: 0,
    }),
  }).then((r) => r.json());
  expect((await a()).skins).toHaveLength(BUILTIN_SKINS.length + 1);
  await b();
  const applied = await fetch(url + '/admin-api/skins', {
    method: 'PATCH',
    headers,
    body: JSON.stringify({ activeSkinId: saved.savedSkinId, expectedRevision: saved.revision }),
  }).then((r) => r.json());
  expect((await a()).activeSkinId).toBe(saved.savedSkinId);
  expect((await b()).revision).toBe(applied.revision);
  expect((await fetch(url + '/appearance').then((r) => r.json())).activeSkinId).toBe(
    saved.savedSkinId,
  );
});
