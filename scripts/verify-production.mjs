import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from '@playwright/test';

const baseURL = process.env.PRODUCTION_URL ?? 'http://127.0.0.1:4173';
const server = process.env.PRODUCTION_URL
  ? null
  : spawn(process.execPath, ['dist-server/index.js'], {
      windowsHide: true,
      stdio: 'pipe',
      env: { ...process.env, PORT: '4173' },
    });
let browser;
try {
  let ready = false;
  for (let i = 0; i < 40; i++) {
    try {
      ready = (await fetch(baseURL, { signal: AbortSignal.timeout(5000) })).ok;
    } catch {
      /* Wait for the preview server. */
    }
    if (ready) break;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  if (!ready) throw new Error('Production preview did not start. Run npm run build first.');
  const edge = join(
    process.env['PROGRAMFILES(X86)'] ?? '',
    'Microsoft',
    'Edge',
    'Application',
    'msedge.exe',
  );
  const channel =
    process.env.PLAYWRIGHT_CHANNEL ??
    (!existsSync(chromium.executablePath()) && existsSync(edge) ? 'msedge' : undefined);
  browser = await chromium.launch({ channel });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (['error', 'warning'].includes(message.type())) errors.push(message.text());
  });
  await page.goto(baseURL);
  await page.getByRole('button', { name: 'Вдвоём', exact: true }).click();
  await page.getByRole('button', { name: 'Начать игру', exact: true }).click();
  await page.getByRole('button', { name: /Начать/ }).click();
  await page.locator('canvas').waitFor();
  await page.waitForTimeout(1200);
  if (await page.evaluate(() => '__fourScene' in window))
    throw new Error('Development projection hook leaked into production.');
  const canvas = await page.locator('canvas').boundingBox();
  if (!canvas) throw new Error('No production canvas');
  await page.mouse.click(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2);
  await page.waitForFunction(() =>
    document.querySelector('[data-testid="move-count"]')?.textContent?.startsWith('1'),
  );
  await page.waitForTimeout(500);
  if (errors.length) throw new Error(errors.join('\n'));
  const ai = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  ai.on('pageerror', (error) => errors.push(error.message));
  ai.on('console', (message) => {
    if (['error', 'warning'].includes(message.type())) errors.push(message.text());
  });
  await ai.goto(baseURL);
  await ai.getByRole('button', { name: 'Вдвоём', exact: true }).click();
  await ai
    .getByRole('dialog')
    .getByRole('button', { name: /Против AI/ })
    .click();
  await ai.getByRole('button', { name: 'Сложно', exact: true }).click();
  await ai.getByRole('button', { name: 'Начать игру', exact: true }).click();
  await ai.getByRole('button', { name: /Начать/ }).click();
  await ai.locator('canvas').waitFor();
  await ai.waitForTimeout(1200);
  const aiBoard = await ai.locator('canvas').boundingBox();
  if (!aiBoard) throw new Error('No production AI canvas');
  await ai.mouse.click(aiBoard.x + aiBoard.width / 2, aiBoard.y + aiBoard.height / 2);
  await ai.waitForFunction(
    () => document.querySelector('[data-testid="move-count"]')?.textContent?.trim() === '2 / 125',
  );
  await ai.waitForTimeout(500);
  await ai.screenshot({ path: 'artifacts/ai-production.png', fullPage: true });
  const host = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const guest = await browser.newPage({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
  });
  for (const client of [host, guest]) {
    client.on('pageerror', (error) => errors.push(error.message));
    client.on('console', (message) => {
      if (['error', 'warning'].includes(message.type())) errors.push(message.text());
    });
    await client.goto(baseURL);
    await client.getByRole('button', { name: 'Онлайн', exact: true }).click();
  }
  await host.getByRole('button', { name: 'Создать лобби', exact: true }).click();
  await host.getByTestId('lobby-code').waitFor();
  const code = await host.getByTestId('lobby-code').innerText();
  if (!/^[A-Z]{5}$/.test(code)) throw new Error('Invalid production lobby code');
  await host.screenshot({ path: 'artifacts/online-lobby.png', fullPage: true });
  await guest.getByRole('textbox', { name: 'Код лобби', exact: true }).fill(code);
  await guest.getByRole('button', { name: 'Войти в лобби', exact: true }).click();
  await guest.getByTestId('lobby-code').waitFor();
  for (const [index, client] of [host, guest].entries()) {
    await client.getByTestId('turn-status').filter({ hasText: 'Ваш ход' }).waitFor();
    await client.waitForTimeout(1000);
    const board = await client.locator('canvas').boundingBox();
    if (!board) throw new Error('Missing online canvas');
    if (index === 0)
      await client.mouse.click(board.x + board.width / 2, board.y + board.height / 2);
    else await client.touchscreen.tap(board.x + board.width / 2, board.y + board.height / 2);
    for (const peer of [host, guest])
      await peer.waitForFunction(
        (count) =>
          document
            .querySelector('[data-testid="move-count"]')
            ?.textContent?.trim()
            .startsWith(String(count)),
        index + 1,
      );
  }
  await guest.waitForTimeout(500);
  await guest.screenshot({ path: 'artifacts/online-mobile.png', fullPage: true });
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'Production smoke passed: local move, hard AI worker reply, and online lobby with two synchronized browser clients (desktop click + mobile tap); no console errors/warnings; dev hook absent.',
  );
} finally {
  await browser?.close();
  server?.kill();
}
