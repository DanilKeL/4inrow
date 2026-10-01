import { expect, test } from '@playwright/test';
import { openGame, place } from './helpers';

test('large screens respect the render pixel budget while phones retain detail', async ({
  browser,
  baseURL,
}) => {
  const context = await browser.newContext({
    baseURL,
    deviceScaleFactor: 2,
    viewport: { width: 1920, height: 1080 },
  });
  const page = await context.newPage();
  const ratio = () =>
    page.locator('canvas').evaluate((canvas) => {
      const width = canvas.getBoundingClientRect().width;
      return (canvas as HTMLCanvasElement).width / width;
    });
  const canvasWidth = () =>
    page.locator('canvas').evaluate((canvas) => canvas.getBoundingClientRect().width);
  try {
    await page.goto('/');
    await expect(page.getByRole('button', { name: 'Вдвоём', exact: true })).toBeVisible();
    await page.locator('.game-scene').evaluate((scene) => {
      scene.style.width = '1920px';
      scene.style.height = '1080px';
    });
    await expect.poll(canvasWidth).toBeGreaterThan(1900);
    await expect.poll(ratio).toBeGreaterThan(1.1);
    await expect.poll(ratio).toBeLessThan(1.3);
    await page.locator('.game-scene').evaluate((scene) => {
      scene.style.width = '';
      scene.style.height = '';
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await expect.poll(canvasWidth).toBeLessThan(390);
    await expect.poll(ratio).toBeGreaterThan(1.98);
    await expect.poll(ratio).toBeLessThanOrEqual(2);
  } finally {
    await context.close();
  }
});

test('high-density phones retain sharpness after timer ticks, moves and rotation', async ({
  browser,
  baseURL,
}, testInfo) => {
  const context = await browser.newContext({
    baseURL,
    deviceScaleFactor: 3,
    isMobile: true,
    hasTouch: true,
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  const ratio = () =>
    page
      .locator('canvas')
      .evaluate(
        (canvas) => (canvas as HTMLCanvasElement).width / canvas.getBoundingClientRect().width,
      );
  try {
    await openGame(page);
    // The one-second game timer used to reconfigure Canvas with DPR 1.
    await page.waitForTimeout(1250);
    await expect.poll(ratio).toBeGreaterThan(2.98);
    await place(page, 2, 2, 1, true);
    await page.waitForTimeout(1250);
    await expect.poll(ratio).toBeGreaterThan(2.98);
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.getByRole('button', { name: 'Сверху', exact: true }).click();
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await expect.poll(ratio).toBeGreaterThan(2.98);
    await page.setViewportSize({ width: 844, height: 390 });
    await page.waitForTimeout(1250);
    await expect.poll(ratio).toBeGreaterThan(2.98);
    await expect
      .poll(() =>
        page
          .locator('canvas')
          .evaluate(
            (canvas) => (canvas as HTMLCanvasElement).width * (canvas as HTMLCanvasElement).height,
          ),
      )
      .toBeLessThanOrEqual(3_000_000);
    await page.screenshot({ path: testInfo.outputPath('phone-sharp-landscape.png') });
  } finally {
    await context.close();
  }
});
