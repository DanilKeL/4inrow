import { chromium } from '@playwright/test';
import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const edge = join(
  process.env['PROGRAMFILES(X86)'] ?? '',
  'Microsoft',
  'Edge',
  'Application',
  'msedge.exe',
);
const browser = await chromium.launch({
  channel: !existsSync(chromium.executablePath()) && existsSync(edge) ? 'msedge' : undefined,
});
const output = 'public/tutorial';
await mkdir(output, { recursive: true });
try {
  const page = await browser.newPage({
    viewport: { width: 960, height: 640 },
    deviceScaleFactor: 1,
  });
  page.on('pageerror', (error) => {
    throw error;
  });
  await page.goto('http://127.0.0.1:5173/scripts/tutorial-render.html');
  await page.waitForFunction(() => window.lessonReady);
  const ids = [
    'stacking',
    'horizontal',
    'vertical',
    'diagonal-flat',
    'diagonal-third-layer',
    'diagonal-space',
  ];
  for (const [index, id] of ids.entries()) {
    if (process.argv[2] && process.argv[2] !== id) continue;
    const result = await page.evaluate((index) => window.recordLesson(index), index);
    const extension = result.mime.startsWith('video/mp4') ? 'mp4' : 'webm';
    await writeFile(`${output}/${id}.${extension}`, Buffer.from(result.bytes));
    await writeFile(`${output}/${id}.webp`, Buffer.from(result.poster.split(',')[1], 'base64'));
    console.log(`${id}: ${extension}, ${Math.round(result.bytes.length / 1024)} KB`);
  }
} finally {
  await browser.close();
}
