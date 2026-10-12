import { createHash } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AuthError } from './auth.ts';

export const MAX_SKIN_ASSET_BYTES = 512 * 1024;
export const MAX_SKIN_ASSET_DIMENSION = 1024;
export const SKIN_ASSET_JSON_LIMIT = Math.ceil(MAX_SKIN_ASSET_BYTES / 3) * 4 + 1024;
const MAX_ASSETS = 256;
const MAX_TOTAL_BYTES = 64 * 1024 * 1024;
const assetId = (id: unknown): id is string => typeof id === 'string' && /^[a-f0-9]{64}$/.test(id);
type ImageInfo = { mime: 'image/png' | 'image/jpeg' | 'image/webp'; width: number; height: number };
export type SkinAsset = ImageInfo & { id: string; bytes: Buffer };

function invalid(): never {
  throw new AuthError(400, 'Нужна корректная картинка PNG, JPEG или WebP.');
}
function dimensions(info: ImageInfo): ImageInfo {
  if (
    !Number.isInteger(info.width) ||
    !Number.isInteger(info.height) ||
    info.width < 1 ||
    info.height < 1 ||
    info.width > MAX_SKIN_ASSET_DIMENSION ||
    info.height > MAX_SKIN_ASSET_DIMENSION
  )
    throw new AuthError(
      400,
      `Размер картинки не должен превышать ${MAX_SKIN_ASSET_DIMENSION} × ${MAX_SKIN_ASSET_DIMENSION}.`,
    );
  return info;
}
function crc32(data: Buffer) {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function pngInfo(bytes: Buffer): ImageInfo {
  let offset = 8;
  let info: ImageInfo | undefined;
  let imageData = false;
  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    if (length > bytes.length - offset - 12) invalid();
    const end = offset + 8 + length;
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (crc32(bytes.subarray(offset + 4, end)) !== bytes.readUInt32BE(end)) invalid();
    if (!info && type !== 'IHDR') invalid();
    if (type === 'IHDR') {
      if (info || length !== 13) invalid();
      const depth = bytes[offset + 16];
      const color = bytes[offset + 17];
      const depths: Record<number, number[]> = {
        0: [1, 2, 4, 8, 16],
        2: [8, 16],
        3: [1, 2, 4, 8],
        4: [8, 16],
        6: [8, 16],
      };
      if (
        !depths[color]?.includes(depth) ||
        bytes[offset + 18] !== 0 ||
        bytes[offset + 19] !== 0 ||
        bytes[offset + 20] > 1
      )
        invalid();
      info = dimensions({
        mime: 'image/png',
        width: bytes.readUInt32BE(offset + 8),
        height: bytes.readUInt32BE(offset + 12),
      });
    } else if (type === 'IDAT') imageData ||= length > 0;
    else if (type === 'acTL')
      invalid(); // Static textures only; no animated image payloads.
    else if (type === 'IEND') {
      if (length || !imageData || end + 4 !== bytes.length) invalid();
      return info!;
    }
    offset = end + 4;
  }
  return invalid();
}
function jpegInfo(bytes: Buffer): ImageInfo {
  if (bytes.length < 8 || bytes.readUInt16BE(bytes.length - 2) !== 0xffd9) invalid();
  let offset = 2;
  let info: ImageInfo | undefined;
  const frames = new Set([0xc0, 0xc1, 0xc2]);
  while (offset + 3 < bytes.length) {
    if (bytes[offset++] !== 0xff) invalid();
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9 || offset + 2 > bytes.length) invalid();
    const length = bytes.readUInt16BE(offset);
    if (length < 2 || offset + length > bytes.length) invalid();
    if (frames.has(marker)) {
      if (info || length < 8 || bytes[offset + 2] !== 8) invalid();
      const components = bytes[offset + 7];
      if (![1, 3, 4].includes(components) || length !== 8 + components * 3) invalid();
      info = dimensions({
        mime: 'image/jpeg',
        height: bytes.readUInt16BE(offset + 3),
        width: bytes.readUInt16BE(offset + 5),
      });
    }
    if (marker === 0xda) {
      if (!info || offset + length >= bytes.length - 2) invalid();
      return info;
    }
    offset += length;
  }
  return invalid();
}
function webpInfo(bytes: Buffer): ImageInfo {
  if (bytes.length < 20 || bytes.readUInt32LE(4) !== bytes.length - 8) invalid();
  let offset = 12;
  let info: ImageInfo | undefined;
  let pixels = false;
  while (offset + 8 <= bytes.length) {
    const type = bytes.toString('ascii', offset, offset + 4);
    const length = bytes.readUInt32LE(offset + 4);
    const data = offset + 8;
    if (length > bytes.length - data) invalid();
    if (type === 'ANIM' || type === 'ANMF') invalid();
    if (type === 'VP8X') {
      if (offset !== 12 || length !== 10 || bytes[data] & 0x02) invalid();
      info = dimensions({
        mime: 'image/webp',
        width: bytes.readUIntLE(data + 4, 3) + 1,
        height: bytes.readUIntLE(data + 7, 3) + 1,
      });
    } else if (type === 'VP8 ') {
      if (
        length <= 10 ||
        pixels ||
        bytes[data] & 1 ||
        bytes.toString('hex', data + 3, data + 6) !== '9d012a'
      )
        invalid();
      const frame = dimensions({
        mime: 'image/webp',
        width: bytes.readUInt16LE(data + 6) & 0x3fff,
        height: bytes.readUInt16LE(data + 8) & 0x3fff,
      });
      if (info && (info.width !== frame.width || info.height !== frame.height)) invalid();
      info = frame;
      pixels = true;
    } else if (type === 'VP8L') {
      if (length <= 5 || pixels || bytes[data] !== 0x2f) invalid();
      const packed = bytes.readUInt32LE(data + 1);
      if (packed >>> 29) invalid();
      const frame = dimensions({
        mime: 'image/webp',
        width: (packed & 0x3fff) + 1,
        height: ((packed >>> 14) & 0x3fff) + 1,
      });
      if (info && (info.width !== frame.width || info.height !== frame.height)) invalid();
      info = frame;
      pixels = true;
    }
    offset = data + length + (length & 1);
  }
  if (!info || !pixels || offset !== bytes.length) invalid();
  return info;
}
function inspect(bytes: Buffer): ImageInfo {
  if (bytes.length >= 8 && bytes.toString('hex', 0, 8) === '89504e470d0a1a0a')
    return pngInfo(bytes);
  if (bytes.length >= 2 && bytes.readUInt16BE(0) === 0xffd8) return jpegInfo(bytes);
  if (
    bytes.length >= 12 &&
    bytes.toString('ascii', 0, 4) === 'RIFF' &&
    bytes.toString('ascii', 8, 12) === 'WEBP'
  )
    return webpInfo(bytes);
  return invalid();
}

/** Content-addressed raster textures are part of the backed-up statistics database. */
export class SkinAssetsStore {
  constructor(private db: DatabaseSync) {
    db.exec(`CREATE TABLE IF NOT EXISTS skin_assets (
      id TEXT PRIMARY KEY, mime TEXT NOT NULL, width INTEGER NOT NULL,
      height INTEGER NOT NULL, bytes BLOB NOT NULL, created INTEGER NOT NULL
    )`);
  }
  has(id: unknown): boolean {
    return assetId(id) && !!this.db.prepare('SELECT 1 FROM skin_assets WHERE id=?').get(id);
  }
  get(id: unknown): SkinAsset | null {
    if (!assetId(id)) return null;
    const row = this.db
      .prepare('SELECT mime,width,height,bytes FROM skin_assets WHERE id=?')
      .get(id);
    return row
      ? {
          id,
          mime: row.mime as ImageInfo['mime'],
          width: Number(row.width),
          height: Number(row.height),
          bytes: Buffer.from(row.bytes as Uint8Array),
        }
      : null;
  }
  save(dataUrl: unknown): { id: string; url: string } {
    if (typeof dataUrl !== 'string') invalid();
    if (dataUrl.length > SKIN_ASSET_JSON_LIMIT)
      throw new AuthError(413, 'Картинка должна весить не больше 512 КБ.');
    const match = /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/]+={0,2})$/.exec(dataUrl);
    if (!match || match[2].length % 4 !== 0) invalid();
    const bytes = Buffer.from(match[2], 'base64');
    if (bytes.length > MAX_SKIN_ASSET_BYTES)
      throw new AuthError(413, 'Картинка должна весить не больше 512 КБ.');
    if (bytes.toString('base64') !== match[2]) invalid();
    const info = inspect(bytes);
    if (info.mime !== match[1]) invalid();
    const id = createHash('sha256').update(bytes).digest('hex');
    if (!this.has(id)) {
      const usage = this.db
        .prepare(
          'SELECT COUNT(*) AS count, COALESCE(SUM(length(bytes)),0) AS size FROM skin_assets',
        )
        .get()!;
      if (Number(usage.count) >= MAX_ASSETS || Number(usage.size) + bytes.length > MAX_TOTAL_BYTES)
        throw new AuthError(409, 'Хранилище картинок заполнено.');
      this.db
        .prepare('INSERT INTO skin_assets(id,mime,width,height,bytes,created) VALUES(?,?,?,?,?,?)')
        .run(id, info.mime, info.width, info.height, bytes, Date.now());
    }
    return { id, url: `/appearance/assets/${id}` };
  }
}
