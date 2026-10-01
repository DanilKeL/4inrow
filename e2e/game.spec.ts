import { test, expect } from '@playwright/test';
import {
  collectErrors,
  columnPosition,
  expectColumnsInsideCanvas,
  openGame,
  place,
  screenshotDifference,
} from './helpers';

test('real canvas local win, replay and rematch', async ({ page }, testInfo) => {
  const errors = collectErrors(page);
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Вдвоём', exact: true })).toBeVisible();
  await page.waitForFunction(() => Boolean(window.__fourScene));
  await page.waitForTimeout(750);
  await page.screenshot({ path: testInfo.outputPath('desktop-menu.png'), fullPage: true });
  await openGame(page);
  const moves = [
    [0, 0],
    [0, 1],
    [1, 0],
    [1, 1],
    [2, 0],
    [2, 1],
    [3, 0],
  ];
  for (let index = 0; index < moves.length; index++) {
    await place(page, moves[index][0], moves[index][1], index + 1);
  }
  await expect(page.getByRole('heading', { name: /Победа: Гость_\d{6}/ })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('desktop-game.png'), fullPage: true });
  await page.getByRole('button', { name: 'Повтор партии' }).click();
  await page.getByRole('button', { name: 'В начало повтора' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  await page.getByRole('button', { name: 'Следующий ход' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('1 / 125');
  await page.getByRole('button', { name: 'В конец повтора' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('7 / 125');
  await page.getByRole('button', { name: 'Завершить просмотр' }).click();
  await page.getByRole('button', { name: 'Ещё партия' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  await place(page, 2, 2, 1);
  expect(errors).toEqual([]);
});

test('empty cell dots remain visible after victory and with hints disabled', async ({ page }) => {
  await openGame(page);
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('switch', { name: 'Анимации' }).uncheck();
  await page.getByRole('switch', { name: 'Предпросмотр хода' }).uncheck();
  await page.getByRole('button', { name: 'Закрыть', exact: true }).click();
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.getByRole('button', { name: 'Сверху', exact: true }).click();
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  const expectDot = async () => {
    await page.mouse.move(10, 10);
    const point = await columnPosition(page, 4, 4);
    const patch = await page.screenshot({
      clip: { x: point.screenX - 4, y: point.screenY - 4, width: 8, height: 8 },
    });
    const markerPixels = await page.evaluate(async (encoded) => {
      const image = new Image();
      image.src = `data:image/png;base64,${encoded}`;
      await image.decode();
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 8;
      const ctx = canvas.getContext('2d')!;
      ctx.drawImage(image, 0, 0);
      const { data } = ctx.getImageData(0, 0, 8, 8);
      let count = 0;
      for (let i = 0; i < data.length; i += 4) {
        if (
          data[i] > 130 &&
          data[i] < 185 &&
          data[i + 1] > 130 &&
          data[i + 1] < 185 &&
          data[i + 2] < 180
        )
          count++;
      }
      return count;
    }, patch.toString('base64'));
    expect(markerPixels).toBeGreaterThan(0);
  };
  await expectDot();
  const moves = [
    [0, 0],
    [0, 1],
    [1, 0],
    [1, 1],
    [2, 0],
    [2, 1],
    [3, 0],
  ];
  for (const [i, [x, y]] of moves.entries()) await place(page, x, y, i + 1);
  await expect(page.getByRole('heading', { name: /Победа: Гость_\d{6}/ })).toBeVisible();
  await expectDot();
});

test('stack caps at five, undo restores a slot, camera drag does not place', async ({ page }) => {
  const errors = collectErrors(page);
  await openGame(page);
  for (let count = 1; count <= 5; count++) await place(page, 2, 2, count);
  const point = await columnPosition(page, 2, 2);
  await page.mouse.click(point.screenX, point.screenY);
  await page.waitForTimeout(500);
  await expect(page.getByTestId('move-count')).toHaveText('5 / 125');
  await page.getByRole('button', { name: 'Отменить ход' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('4 / 125');
  await page.waitForTimeout(500);
  await place(page, 2, 2, 5);
  const origin = await columnPosition(page, 1, 1);
  await page.mouse.move(origin.screenX, origin.screenY);
  await page.mouse.down();
  await page.mouse.move(origin.screenX + 100, origin.screenY + 35, { steps: 12 });
  await page.mouse.up();
  await page.waitForTimeout(500);
  await expect(page.getByTestId('move-count')).toHaveText('5 / 125');
  const rotated = await columnPosition(page, 1, 1);
  expect(
    Math.hypot(rotated.screenX - origin.screenX, rotated.screenY - origin.screenY),
  ).toBeGreaterThan(5);
  await place(page, 1, 1, 6);
  await page.getByRole('button', { name: 'Сбросить вид' }).click();
  await page.getByRole('button', { name: 'Рентген', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Рентген', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  expect(errors).toEqual([]);
});

test('hard AI responds through its worker and undo removes the pair', async ({ page }) => {
  const errors = collectErrors(page);
  await openGame(page, 'ai');
  await place(page, 2, 2, 1);
  await expect(page.getByTestId('move-count')).toHaveText('2 / 125');
  await expect(page.getByTestId('turn-status')).toContainText(/Гость_\d{6}/);
  await page.waitForTimeout(500);
  await page.getByRole('button', { name: 'Отменить ход' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  expect(errors).toEqual([]);
});

test('settings persist after reload', async ({ page }) => {
  const errors = collectErrors(page);
  await page.goto('/');
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await expect(page.getByRole('switch', { name: 'Звуки игры' })).toHaveCount(0);
  await expect(page.getByText('Фоновый звук', { exact: true })).toHaveCount(0);
  await page.getByRole('slider', { name: 'Громкость звуков' }).fill('37');
  await page.getByRole('switch', { name: 'Рентген по умолчанию' }).check();
  await page.reload();
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await expect(page.getByRole('slider', { name: 'Громкость звуков' })).toHaveValue('37');
  await expect(page.getByRole('switch', { name: 'Рентген по умолчанию' })).toBeChecked();
  expect(errors).toEqual([]);
});

test('pause blocks board moves and resume continues the same match', async ({ page }) => {
  const errors = collectErrors(page);
  await openGame(page);
  await place(page, 2, 2, 1);
  await page.getByRole('button', { name: 'Пауза', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Пауза' })).toBeVisible();
  await expect(page.getByTestId('move-count')).toHaveText('1 / 125');
  await page.getByRole('button', { name: 'Продолжить', exact: true }).click();
  await place(page, 2, 2, 2);
  expect(errors).toEqual([]);
});

test('a real spatial diagonal wins through all three dimensions', async ({ page }) => {
  const errors = collectErrors(page);
  await openGame(page);
  // The final line is (0,0,0), (1,1,1), (2,2,2), (3,3,3).
  const moves = [
    [0, 0],
    [1, 1],
    [1, 1],
    [2, 2],
    [2, 2],
    [3, 3],
    [2, 2],
    [3, 3],
    [3, 3],
    [4, 0],
    [3, 3],
  ];
  for (let index = 0; index < moves.length; index++) {
    await place(page, moves[index][0], moves[index][1], index + 1);
    if (index < moves.length - 1)
      await expect(page.getByRole('heading', { name: /Победа:/ })).toHaveCount(0);
  }
  await expect(page.getByRole('heading', { name: /Победа: Гость_\d{6}/ })).toBeVisible();
  expect(errors).toEqual([]);
});

test('x-ray and layer selection change the actual rendered board', async ({ page }) => {
  const errors = collectErrors(page);
  await openGame(page);
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('switch', { name: 'Анимации' }).uncheck();
  await page.getByRole('switch', { name: 'Предпросмотр хода' }).uncheck();
  await page.getByRole('button', { name: 'Закрыть', exact: true }).click();
  for (let index = 1; index <= 5; index++) await place(page, 2, 2, index);
  await page.mouse.move(10, 10);
  await page.waitForTimeout(300);
  const canvas = page.locator('canvas');
  const opaque = await canvas.screenshot();
  const idleDifference = await screenshotDifference(page, opaque, await canvas.screenshot());
  expect(idleDifference).toBeLessThan(0.002);
  await page.getByRole('button', { name: 'Рентген', exact: true }).click();
  await page.waitForTimeout(150);
  expect(await screenshotDifference(page, opaque, await canvas.screenshot())).toBeGreaterThan(
    Math.max(0.002, idleDifference * 5),
  );
  await page.getByRole('button', { name: 'Рентген', exact: true }).click();
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.getByRole('button', { name: 'Слой 1', exact: true }).click();
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.waitForTimeout(150);
  expect(await screenshotDifference(page, opaque, await canvas.screenshot())).toBeGreaterThan(
    Math.max(0.002, idleDifference * 5),
  );
  expect(errors).toEqual([]);
});

test('desktop sizes keep all 25 columns inside default and top cameras', async ({ page }) => {
  const errors = collectErrors(page);
  await openGame(page);
  for (const [width, height] of [
    [1920, 1080],
    [1440, 900],
    [1366, 768],
  ]) {
    await page.setViewportSize({ width, height });
    await page.getByRole('button', { name: 'Сбросить вид' }).click();
    await page.waitForTimeout(900);
    await expectColumnsInsideCanvas(page);
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.getByRole('button', { name: 'Сверху', exact: true }).click();
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.waitForTimeout(900);
    await expectColumnsInsideCanvas(page);
  }
  expect(errors).toEqual([]);
});
