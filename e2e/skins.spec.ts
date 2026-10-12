import { expect, test } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { createHash } from 'node:crypto';
let server: ChildProcess;
let url: string;
test.beforeAll(async () => {
  server = spawn(process.execPath, ['--import', 'tsx', 'e2e/skins-server.ts'], {
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  url = await new Promise<string>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Skin test server did not start')), 10000);
    server.stdout!.on('data', (data) => {
      const match = /http:\/\/127\.0\.0\.1:\d+/.exec(String(data));
      if (match) {
        clearTimeout(timer);
        resolve(match[0]);
      }
    });
    server.once('error', reject);
  });
});
test.afterAll(async () => {
  if (server?.exitCode === null)
    await new Promise<void>((resolve) => {
      server.once('exit', () => resolve());
      server.kill();
    });
});
test('admin creates skins, previews without changing the game, applies live and retains the style offline', async ({
  browser,
}, info) => {
  test.setTimeout(90000);
  const players = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const adminContext = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const player = await players.newPage(),
    admin = await adminContext.newPage();
  const errors: string[] = [];
  player.on('pageerror', (error) => errors.push(error.message));
  admin.on('pageerror', (error) => errors.push(error.message));
  const style = () =>
    player.evaluate(
      () => JSON.parse(localStorage.getItem('four-skins-v1') ?? '{}').activeSkinId as string,
    );
  const signature = async () =>
    createHash('sha256')
      .update(await player.getByTestId('game-canvas').screenshot())
      .digest('hex');
  try {
    await player.goto(url);
    await expect(player.getByTestId('loading-screen')).not.toBeVisible();
    await expect.poll(style).toBe('coffee-board');
    await player.waitForTimeout(1700);
    const coffeeBoard = await signature();
    await admin.goto(url + '/admin');
    await admin.getByLabel('Пароль').fill('skin-browser-test-123');
    await admin.getByRole('button', { name: 'Войти', exact: true }).click();
    await admin.getByRole('button', { name: 'Оформление', exact: true }).click();
    await expect(admin.getByRole('button', { name: /Кофейная доска/ })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    await admin.getByRole('button', { name: /Классика/ }).click();
    expect(await style()).toBe('coffee-board');
    await admin.getByRole('button', { name: 'Применить для всех' }).click();
    await expect.poll(style).toBe('classic');
    expect(await signature()).not.toBe(coffeeBoard);
    await admin.getByRole('button', { name: 'Новый стиль' }).click();
    await admin.getByLabel('Название стиля').fill('Мокко');
    await admin.getByLabel('Поверхность доски').fill('#ad896c');
    expect(await style()).toBe('classic');
    await admin.screenshot({ path: info.outputPath('skin-editor-desktop.png') });
    await admin.getByRole('button', { name: 'Сохранить стиль' }).click();
    await expect(admin.getByRole('status')).toHaveText('Стиль сохранён.');
    await admin.getByRole('button', { name: 'Применить для всех' }).click();
    await expect.poll(style).toMatch(/^custom-/);
    const custom = await style();
    await admin.getByRole('button', { name: 'Изменить', exact: true }).click();
    await admin.getByLabel('Верх светлых фишек').fill('#ffddaa');
    await admin.getByRole('button', { name: 'Сохранить стиль' }).click();
    await expect
      .poll(() =>
        player.evaluate(() => {
          const data = JSON.parse(localStorage.getItem('four-skins-v1')!);
          return data.skins.find((skin: { id: string }) => skin.id === data.activeSkinId).palette
            .light.cap;
        }),
      )
      .toBe('#ffddaa');
    await player.screenshot({ path: info.outputPath('skin-live-mobile.png') });
    await admin.setViewportSize({ width: 390, height: 844 });
    expect(await admin.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(
      true,
    );
    await admin.screenshot({ path: info.outputPath('skin-panel-mobile.png') });
    await players.setOffline(true);
    await player.reload();
    await expect(player.getByTestId('loading-screen')).not.toBeVisible();
    expect(await style()).toBe(custom);
    await players.setOffline(false);
    await admin.getByRole('button', { name: /Кофейная доска/ }).click();
    await admin.getByRole('button', { name: 'Применить для всех' }).click();
    await expect.poll(style).toBe('coffee-board');
    await admin.getByRole('button', { name: /Мокко/ }).click();
    await admin.getByRole('button', { name: 'Удалить', exact: true }).click();
    await expect(admin.getByRole('button', { name: /Мокко/ })).toHaveCount(0);
    expect(errors).toEqual([]);
  } finally {
    await players.close();
    await adminContext.close();
  }
});
