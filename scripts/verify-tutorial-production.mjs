import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { chromium, expect } from '@playwright/test';

const url = process.env.PRODUCTION_URL ?? 'http://127.0.0.1:4175';
const server = process.env.PRODUCTION_URL
  ? null
  : spawn(process.execPath, ['dist-server/index.js'], {
      windowsHide: true,
      stdio: 'pipe',
      env: { ...process.env, PORT: '4175' },
    });
let browser;
try {
  let ready = false;
  for (let i = 0; i < 20; i++) {
    try {
      ready = (await fetch(url, { signal: AbortSignal.timeout(2000) })).ok;
    } catch {
      /* Retry startup / connection. */
    }
    if (ready) break;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  if (!ready) throw new Error('Production server unavailable');
  const edge = join(
    process.env['PROGRAMFILES(X86)'] ?? '',
    'Microsoft',
    'Edge',
    'Application',
    'msedge.exe',
  );
  browser = await chromium.launch({
    channel: !existsSync(chromium.executablePath()) && existsSync(edge) ? 'msedge' : undefined,
  });
  const page = await browser.newPage({ viewport: { width: 1366, height: 768 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(url);
  await page.getByRole('button', { name: 'Как играть', exact: true }).click();
  for (let i = 0; i < 6; i++) {
    await page
      .getByRole('navigation', { name: 'Примеры правил' })
      .getByRole('button')
      .nth(i)
      .click();
    const video = page.locator('video');
    await expect
      .poll(() =>
        video.evaluate(
          (v) =>
            v.readyState >= 2 && v.currentTime > 0.1 && !v.error && Number.isFinite(v.duration),
        ),
      )
      .toBe(true);
    await page.getByRole('button', { name: 'Остановить пример' }).click();
    const ids = [
      'stacking',
      'horizontal',
      'vertical',
      'diagonal-flat',
      'diagonal-third-layer',
      'diagonal-space',
    ];
    const range = await fetch(new URL(`/tutorial/${ids[i]}.mp4`, url), {
      headers: { Range: 'bytes=0-1' },
    });
    expect(range.status).toBe(206);
    expect(range.headers.get('content-type')).toBe('video/mp4');
    expect((await range.arrayBuffer()).byteLength).toBe(2);
    await video.evaluate((v) => {
      v.currentTime = v.duration - 0.2;
    });
  }
  await page.waitForTimeout(300);
  await page.screenshot({ path: 'artifacts/tutorial-production-desktop.png' });
  await page.setViewportSize({ width: 320, height: 568 });
  await page.waitForTimeout(300);
  await page.screenshot({ path: 'artifacts/tutorial-production-mobile.png' });
  expect(errors).toEqual([]);
  console.log(
    'Production tutorial passed: all six MP4 clips decode, play and seek; video/mp4 MIME and HTTP 206 byte ranges; no page errors.',
  );
} finally {
  await browser?.close();
  server?.kill();
}
