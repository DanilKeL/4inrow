import { chromium } from '@playwright/test';
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

// Rasterize the existing vector logo for mobile notifications and Home Screen icons.
const svg = await readFile(new URL('../public/favicon.svg', import.meta.url), 'utf8');
const directory = new URL('../public/icons/', import.meta.url);
await mkdir(directory, { recursive: true });
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL || 'msedge' });
try {
  const page = await browser.newPage();
  for (const size of [192, 512]) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(
      `<style>body{margin:0;background:#2955e7}svg{display:block;width:100vw;height:100vh}</style>${svg}`,
    );
    await page.screenshot({ path: fileURLToPath(new URL(`icon-${size}.png`, directory)) });
  }
} finally {
  await browser.close();
}
