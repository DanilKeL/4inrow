import { afterEach, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { deflateSync } from 'node:zlib';
import type { AddressInfo } from 'node:net';
import { SkinAssetsStore, MAX_SKIN_ASSET_BYTES, SKIN_ASSET_JSON_LIMIT } from './skinAssets';
import { createOnlineServer } from './app';
import { createAdminPasswordHash } from './admin';

const databases: DatabaseSync[] = [];
const directories: string[] = [];
let app: ReturnType<typeof createOnlineServer> | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
  databases.splice(0).forEach((db) => db.close());
  directories.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true }));
});
function store(file = ':memory:') {
  const db = new DatabaseSync(file);
  databases.push(db);
  return new SkinAssetsStore(db);
}
function url(bytes: Buffer, mime = 'image/png') {
  return `data:${mime};base64,${bytes.toString('base64')}`;
}
function png(width = 1, height = 1, color = 128) {
  function chunk(type: string, bytes: Buffer) {
    const typed = Buffer.concat([Buffer.from(type), bytes]);
    let crc = 0xffffffff;
    for (const byte of typed) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
    const head = Buffer.alloc(4),
      tail = Buffer.alloc(4);
    head.writeUInt32BE(bytes.length);
    tail.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([head, typed, tail]);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([
    Buffer.from('89504e470d0a1a0a', 'hex'),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(Buffer.from([0, color, 70, 50, 255]))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}
async function server() {
  const password = 'skin-assets-test-123';
  app = createOnlineServer({
    staticDir: null,
    authFile: null,
    statsFile: null,
    telegram: null,
    adminPasswordHash: await createAdminPasswordHash(password),
  });
  await new Promise<void>((resolve) => app!.httpServer.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${(app.httpServer.address() as AddressInfo).port}`;
  const response = await fetch(base + '/admin-api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'admin', password }),
  });
  const cookie = response.headers.getSetCookie()[0].split(';')[0];
  const upload = (body: unknown, extra: Record<string, string> = {}, authenticated = true) =>
    fetch(base + '/admin-api/skin-assets', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(authenticated ? { Cookie: cookie } : {}),
        ...extra,
      },
      body: JSON.stringify(body),
    });
  return { base, cookie, upload };
}

it('persists content-addressed bytes in SQLite and deduplicates uploads without overwriting', () => {
  const dir = mkdtempSync(join(tmpdir(), 'four-skin-assets-'));
  directories.push(dir);
  const file = join(dir, 'statistics.sqlite');
  const assets = store(file);
  const bytes = png();
  const saved = assets.save(url(bytes));
  expect(saved).toEqual({
    id: createHash('sha256').update(bytes).digest('hex'),
    url: `/appearance/assets/${saved.id}`,
  });
  expect(assets.save(url(bytes))).toEqual(saved);
  expect(databases.at(-1)!.prepare('SELECT COUNT(*) AS count FROM skin_assets').get()!.count).toBe(
    1,
  );
  databases.pop()!.close();
  const restored = store(file);
  expect(restored.get(saved.id)).toEqual({
    id: saved.id,
    mime: 'image/png',
    width: 1,
    height: 1,
    bytes,
  });
  expect(restored.has(saved.id)).toBe(true);
  expect(restored.has('../outside')).toBe(false);
  expect(restored.get('a'.repeat(64))).toBeNull();
});
it('accepts real JPEG and WebP images and rejects format spoofing, broken chunks and unreasonable sizes', () => {
  const assets = store();
  const jpeg = readFileSync(new URL('../public/telegram/four-avatar.jpg', import.meta.url));
  const webp = readFileSync(new URL('../public/tutorial/vertical-start.webp', import.meta.url));
  expect(assets.get(assets.save(url(jpeg, 'image/jpeg')).id)).toMatchObject({
    mime: 'image/jpeg',
    width: 512,
    height: 512,
  });
  expect(assets.get(assets.save(url(webp, 'image/webp')).id)).toMatchObject({
    mime: 'image/webp',
    width: 960,
    height: 480,
  });
  const damaged = png();
  damaged[48] ^= 1;
  for (const dataUrl of [
    undefined,
    'https://other.example/texture.png',
    'data:image/svg+xml;base64,' + Buffer.from('<svg/>').toString('base64'),
    url(png(), 'image/jpeg'),
    url(jpeg, 'image/png'),
    url(webp.subarray(0, -1), 'image/webp'),
    url(jpeg.subarray(0, -2), 'image/jpeg'),
    url(Buffer.from('ffd8ffffffffffffd9', 'hex'), 'image/jpeg'),
    url(damaged),
    url(Buffer.from('PNG')),
    url(png()) + '!',
  ])
    expect(() => assets.save(dataUrl)).toThrow('корректная картинка');
  expect(() => assets.save(url(png(1025)))).toThrow('1024');
  expect(() => assets.save(url(png(1, 0)))).toThrow('1024');
  expect(() => assets.save(url(Buffer.alloc(MAX_SKIN_ASSET_BYTES + 1)))).toThrow('512 КБ');
  expect(() => assets.save('x'.repeat(SKIN_ASSET_JSON_LIMIT + 1))).toThrow('512 КБ');
});
it('caps the storage budget while allowing an existing image after the limit is reached', () => {
  const assets = store();
  for (let color = 0; color < 256; color++) assets.save(url(png(1, 1, color)));
  const duplicate = assets.save(url(png(1, 1, 17)));
  expect(assets.has(duplicate.id)).toBe(true);
  expect(() =>
    assets.save(url(readFileSync(new URL('../public/favicon.png', import.meta.url)))),
  ).toThrow('заполнено');
});
it('restricts uploads to same-origin admins and does not raise unrelated admin body limits', async () => {
  const { base, cookie, upload } = await server();
  expect((await upload({ dataUrl: url(png()) }, {}, false)).status).toBe(401);
  expect((await upload({ dataUrl: url(png()) }, { Origin: 'https://other.example' })).status).toBe(
    403,
  );
  expect(
    (await fetch(base + '/admin-api/skin-assets', { headers: { Cookie: cookie } })).status,
  ).toBe(405);
  expect((await upload({ dataUrl: 'data:image/svg+xml;base64,PHN2Zy8+' })).status).toBe(400);
  expect((await upload({ dataUrl: 'x'.repeat(SKIN_ASSET_JSON_LIMIT + 1) })).status).toBe(413);
  expect(
    (
      await fetch(base + '/admin-api/accounts', {
        method: 'PATCH',
        headers: { Cookie: cookie, 'Content-Type': 'application/json' },
        body: JSON.stringify({ ignored: 'x'.repeat(9000) }),
      })
    ).status,
  ).toBe(413);
});
it('serves immutable raster bytes publicly with correct MIME, HEAD and conditional cache reads', async () => {
  const { base, upload } = await server();
  const bytes = readFileSync(new URL('../public/tutorial/vertical-start.webp', import.meta.url));
  expect(bytes.length).toBeGreaterThan(8192);
  const response = await upload({ dataUrl: url(bytes, 'image/webp') });
  expect(response.status).toBe(201);
  const saved = await response.json();
  expect(await (await upload({ dataUrl: url(bytes, 'image/webp') })).json()).toEqual(saved);
  const asset = await fetch(base + saved.url);
  expect(asset.status).toBe(200);
  expect(asset.headers.get('content-type')).toBe('image/webp');
  expect(asset.headers.get('x-content-type-options')).toBe('nosniff');
  expect(asset.headers.get('content-length')).toBe(String(bytes.length));
  expect(asset.headers.get('cache-control')).toContain('immutable');
  expect(Buffer.from(await asset.arrayBuffer())).toEqual(bytes);
  const head = await fetch(base + saved.url, { method: 'HEAD' });
  expect(head.status).toBe(200);
  expect(head.headers.get('content-length')).toBe(String(bytes.length));
  expect(await head.text()).toBe('');
  expect(
    (await fetch(base + saved.url, { headers: { 'If-None-Match': asset.headers.get('etag')! } }))
      .status,
  ).toBe(304);
  expect((await fetch(base + saved.url, { method: 'POST' })).status).toBe(405);
  expect((await fetch(base + '/appearance/assets/invalid')).status).toBe(404);
  expect((await fetch(base + '/appearance/assets/' + 'b'.repeat(64))).status).toBe(404);
});
