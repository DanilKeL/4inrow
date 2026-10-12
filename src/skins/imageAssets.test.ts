// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const id = 'a'.repeat(64);
const fetchImage = () =>
  new Response(new Uint8Array([82, 73, 70, 70, 12, 0, 0, 0]), {
    headers: { 'content-type': 'image/webp' },
  });
let disk: Map<string, Response>;
let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  vi.resetModules();
  disk = new Map();
  const cache = {
    match: vi.fn(async (url: string) => disk.get(url)?.clone()),
    put: vi.fn(async (url: string, response: Response) => {
      disk.set(url, response);
    }),
    keys: vi.fn(async () => [...disk.keys()].map((url) => new Request(`https://4inrow.ru${url}`))),
    delete: vi.fn(async (request: Request) => disk.delete(new URL(request.url).pathname)),
  };
  vi.stubGlobal('caches', { open: vi.fn(async () => cache) });
  fetchMock = vi.fn(async () => fetchImage());
  vi.stubGlobal('fetch', fetchMock);
  vi.stubGlobal(
    'Image',
    class {
      naturalWidth = 256;
      naturalHeight = 256;
      src = '';
      decoding = '';
      decode = vi.fn(async () => undefined);
    },
  );
  vi.stubGlobal(
    'URL',
    class extends URL {
      static createObjectURL = vi.fn(() => 'blob:skin');
      static revokeObjectURL = vi.fn();
    },
  );
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

it('shares concurrent loads, stores the verified image for offline play and releases its blob URL', async () => {
  const { loadSkinImage, getLoadedSkinImage } = await import('./imageAssets');
  const [one, two] = await Promise.all([loadSkinImage(id), loadSkinImage(id)]);
  expect(one).toBe(two);
  expect(getLoadedSkinImage(id)).toBe(one);
  expect(fetchMock).toHaveBeenCalledTimes(1);
  expect(fetchMock.mock.calls[0][0]).toBe(`/appearance/assets/${id}`);
  await vi.waitFor(() => expect(disk.has(`/appearance/assets/${id}`)).toBe(true));
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:skin');
  vi.resetModules();
  fetchMock.mockRejectedValue(new Error('offline'));
  const offline = await import('./imageAssets');
  expect((await offline.loadSkinImage(id)).naturalWidth).toBe(256);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it('rejects arbitrary image URLs, invalid media and oversized data without caching them', async () => {
  const { loadSkinImage } = await import('./imageAssets');
  await expect(loadSkinImage('https://example.com/tracker.svg')).rejects.toThrow();
  expect(fetchMock).not.toHaveBeenCalled();
  fetchMock.mockResolvedValue(
    new Response('<svg/>', { headers: { 'content-type': 'image/svg+xml' } }),
  );
  await expect(loadSkinImage(id)).rejects.toThrow('Неподдерживаемое');
  fetchMock.mockResolvedValue(
    new Response(new Uint8Array(512 * 1024 + 1), { headers: { 'content-type': 'image/png' } }),
  );
  await expect(loadSkinImage(id)).rejects.toThrow('размер');
  expect(disk.size).toBe(0);
});

it('keeps image loading usable when browser storage is unavailable', async () => {
  vi.stubGlobal('caches', {
    open: vi.fn(async () => {
      throw new Error('storage blocked');
    }),
  });
  const { prefetchSkinImages, loadSkinImage } = await import('./imageAssets');
  await prefetchSkinImages([id, id]);
  expect((await loadSkinImage(id)).naturalHeight).toBe(256);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it('publishes newly decoded images after offline recovery without remounting and unsubscribes previews', async () => {
  const { subscribeSkinImages, loadSkinImage, prefetchSkinImages, getLoadedSkinImage } =
    await import('./imageAssets');
  const ready = vi.fn();
  const stop = subscribeSkinImages(ready);
  fetchMock.mockRejectedValueOnce(new Error('offline'));
  await expect(loadSkinImage(id)).rejects.toThrow('offline');
  expect(ready).not.toHaveBeenCalled();
  await prefetchSkinImages([id]);
  expect(ready).toHaveBeenCalledTimes(1);
  expect(ready).toHaveBeenCalledWith(id, getLoadedSkinImage(id));
  await loadSkinImage(id);
  expect(ready).toHaveBeenCalledTimes(1);
  stop();
  await loadSkinImage('b'.repeat(64));
  expect(ready).toHaveBeenCalledTimes(1);
});
