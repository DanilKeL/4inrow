import { readFile, writeFile } from 'node:fs/promises';
import { chromium } from '@playwright/test';

const svg = await readFile('public/favicon.svg', 'utf8');
const manrope = (
  await readFile('node_modules/@fontsource-variable/manrope/files/manrope-latin-wght-normal.woff2')
).toString('base64');
const fontFace = `@font-face{font-family:Manrope;src:url(data:font/woff2;base64,${manrope}) format('woff2');font-weight:200 800;font-style:normal}`;
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL ?? 'msedge' });
const pngs = new Map();
try {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const size of [32, 48, 96, 180, 192, 512]) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(
      `<style>${fontFace}html,body{margin:0;background:transparent}svg{display:block;width:100vw;height:100vh}</style>${svg}`,
    );
    await page.evaluate(() => document.fonts.ready);
    const png = await page.screenshot({ omitBackground: true });
    pngs.set(size, png);
    if (size === 96) await writeFile('public/favicon.png', png);
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

// ICO directory embeds lossless PNG images; supported by current browsers and crawlers.
const sizes = [32, 48];
const header = Buffer.alloc(6 + sizes.length * 16);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
for (const [index, size] of sizes.entries()) {
  const png = pngs.get(size);
  const entry = 6 + index * 16;
  header[entry] = size;
  header[entry + 1] = size;
  header.writeUInt16LE(1, entry + 4);
  header.writeUInt16LE(32, entry + 6);
  header.writeUInt32LE(png.length, entry + 8);
  header.writeUInt32LE(offset, entry + 12);
  offset += png.length;
}
await writeFile(
  'public/favicon.ico',
  Buffer.concat([header, ...sizes.map((size) => pngs.get(size))]),
);
console.log('Generated PNG, ICO, Apple and installation icons from favicon.svg.');
