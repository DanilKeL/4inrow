import { readFile, writeFile } from 'node:fs/promises';
import { chromium } from '@playwright/test';

const svg = await readFile('public/favicon.svg', 'utf8');
const manrope = (
  await readFile('node_modules/@fontsource-variable/manrope/files/manrope-latin-wght-normal.woff2')
).toString('base64');
const fontFace = `@font-face{font-family:Manrope;src:url(data:font/woff2;base64,${manrope}) format('woff2');font-weight:200 800;font-style:normal}`;
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL ?? 'msedge' });
const pngs = new Map();
const bitmaps = new Map();
try {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const size of [16, 32, 48, 96, 120, 180, 192, 512]) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(
      `<style>${fontFace}html,body{margin:0;background:transparent}svg{display:block;width:100vw;height:100vh}</style>${svg}`,
    );
    await page.evaluate(() => document.fonts.ready);
    const png = await page.screenshot({ omitBackground: true });
    pngs.set(size, png);
    if (size <= 48) {
      const pixels = await page.evaluate(async (base64) => {
        const picture = new Image();
        picture.src = `data:image/png;base64,${base64}`;
        await picture.decode();
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = picture.width;
        const context = canvas.getContext('2d');
        context.drawImage(picture, 0, 0);
        return Array.from(context.getImageData(0, 0, canvas.width, canvas.height).data);
      }, png.toString('base64'));
      bitmaps.set(size, iconBitmap(size, pixels));
    }
    if (size === 96) await writeFile('public/favicon.png', png);
    if (size === 120) await writeFile('public/favicon-search.png', png);
    if (size === 180) await writeFile('public/icons/apple-touch-icon.png', png);
    if (size === 192) {
      await writeFile('public/icons/icon-192.png', png);
      await writeFile('public/icons/email-logo.png', png);
    }
    if (size === 512) await writeFile('public/icons/icon-512.png', png);
  }
} finally {
  await browser.close();
}

// Conventional BGRA/DIB frames also work in older favicon parsers; retain a
// high-resolution PNG frame for browsers on displays with a high pixel density.
function iconBitmap(size, rgba) {
  const maskStride = Math.ceil(size / 32) * 4;
  const bitmap = Buffer.alloc(40 + size * size * 4 + maskStride * size);
  bitmap.writeUInt32LE(40, 0);
  bitmap.writeInt32LE(size, 4);
  bitmap.writeInt32LE(size * 2, 8);
  bitmap.writeUInt16LE(1, 12);
  bitmap.writeUInt16LE(32, 14);
  bitmap.writeUInt32LE(size * size * 4 + maskStride * size, 20);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const source = (y * size + x) * 4;
      const row = size - 1 - y;
      const target = 40 + (row * size + x) * 4;
      bitmap[target] = rgba[source + 2];
      bitmap[target + 1] = rgba[source + 1];
      bitmap[target + 2] = rgba[source];
      bitmap[target + 3] = rgba[source + 3];
      if (!rgba[source + 3])
        bitmap[40 + size * size * 4 + row * maskStride + (x >> 3)] |= 0x80 >> (x % 8);
    }
  }
  return bitmap;
}
const sizes = [16, 32, 48, 96];
const frames = sizes.map((size) => bitmaps.get(size) ?? pngs.get(size));
const header = Buffer.alloc(6 + sizes.length * 16);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
for (const [index, size] of sizes.entries()) {
  const frame = frames[index];
  const entry = 6 + index * 16;
  header[entry] = size;
  header[entry + 1] = size;
  header.writeUInt16LE(1, entry + 4);
  header.writeUInt16LE(32, entry + 6);
  header.writeUInt32LE(frame.length, entry + 8);
  header.writeUInt32LE(offset, entry + 12);
  offset += frame.length;
}
await writeFile(
  'public/favicon.ico',
  Buffer.concat([header, ...frames]),
);
console.log('Generated PNG, ICO, Apple and installation icons from favicon.svg.');
