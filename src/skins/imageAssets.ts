const ASSET_CACHE = 'four-skin-assets-v1';
const MAX_BYTES = 512 * 1024;
const MAX_CACHED_IMAGES = 128;
const MAX_DECODED_IMAGES = 16;
const images = new Map<string, HTMLImageElement>();
const pending = new Map<string, Promise<HTMLImageElement>>();
type ImageListener = (id: string, image: HTMLImageElement) => void;
const listeners = new Set<ImageListener>();

export function subscribeSkinImages(listener: ImageListener) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function skinImageUrl(id: string) {
  if (!/^[a-f0-9]{64}$/.test(id)) throw new Error('Некорректное изображение стиля');
  return `/appearance/assets/${id}`;
}

export function getLoadedSkinImage(id: string): HTMLImageElement | undefined {
  return images.get(id);
}

async function storedResponse(url: string): Promise<Response | undefined> {
  try {
    return await (await caches.open(ASSET_CACHE)).match(url);
  } catch {
    // Private browsing and a full device must not prevent the skin from loading.
    return undefined;
  }
}

async function storeResponse(url: string, response: Response) {
  try {
    const cache = await caches.open(ASSET_CACHE);
    await cache.put(url, response);
    const keys = await cache.keys();
    for (const key of keys.slice(0, Math.max(0, keys.length - MAX_CACHED_IMAGES))) {
      await cache.delete(key);
    }
  } catch {
    // This cache is optional; the server and the in-memory copy still work.
  }
}

async function decode(id: string): Promise<HTMLImageElement> {
  const url = skinImageUrl(id);
  let response = await storedResponse(url);
  let networkResponse = false;
  let timeout: ReturnType<typeof setTimeout> | undefined;
  let objectUrl: string | undefined;
  try {
    if (!response) {
      const controller = new AbortController();
      timeout = setTimeout(() => controller.abort(), 12_000);
      response = await fetch(url, { signal: controller.signal, redirect: 'error' });
      if (!response.ok) throw new Error('Не удалось загрузить изображение стиля');
      networkResponse = true;
    }
    const mime = response.headers.get('content-type')?.split(';')[0];
    if (!mime || !['image/png', 'image/jpeg', 'image/webp'].includes(mime)) {
      throw new Error('Неподдерживаемое изображение стиля');
    }
    const blob = await response.clone().blob();
    if (!blob.size || blob.size > MAX_BYTES) throw new Error('Некорректный размер изображения');
    objectUrl = URL.createObjectURL(blob);
    const image = new Image();
    image.decoding = 'async';
    image.src = objectUrl;
    await image.decode();
    if (
      !image.naturalWidth ||
      !image.naturalHeight ||
      image.naturalWidth > 1024 ||
      image.naturalHeight > 1024
    ) {
      throw new Error('Некорректный размер изображения');
    }
    images.set(id, image);
    while (images.size > MAX_DECODED_IMAGES) images.delete(images.keys().next().value!);
    for (const listener of [...listeners]) {
      try {
        listener(id, image);
      } catch {
        /* One detached preview cannot interrupt other clients. */
      }
    }
    if (networkResponse) await storeResponse(url, response);
    return image;
  } finally {
    if (timeout) clearTimeout(timeout);
    if (objectUrl) URL.revokeObjectURL(objectUrl);
  }
}

export function loadSkinImage(id: string): Promise<HTMLImageElement> {
  try {
    skinImageUrl(id);
  } catch (error) {
    return Promise.reject(error);
  }
  const cached = images.get(id);
  if (cached) {
    // Recently used images remain decoded; old ones can be read from disk again.
    images.delete(id);
    images.set(id, cached);
    return Promise.resolve(cached);
  }
  if (!pending.has(id)) {
    const request = decode(id).finally(() => pending.delete(id));
    pending.set(id, request);
  }
  return pending.get(id)!;
}

export async function prefetchSkinImages(ids: readonly string[]) {
  const unique = [...new Set(ids)];
  let index = 0;
  await Promise.all(
    Array.from({ length: Math.min(4, unique.length) }, async () => {
      while (index < unique.length) {
        const id = unique[index++];
        await loadSkinImage(id).catch(() => undefined);
      }
    }),
  );
}
