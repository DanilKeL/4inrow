import { test, expect } from '@playwright/test';
import { collectErrors, screenshotDifference } from './helpers';
import { tutorialExamples } from '../src/ui/tutorialExamples';

test('initial screen waits for all videos, rules reuse downloaded files and reload uses disk cache', async ({
  page,
}) => {
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  const requests: string[] = [];
  await page.route('**/tutorial/*.mp4', async (route) => {
    requests.push(route.request().url());
    await gate;
    await route.continue();
  });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect.poll(() => requests.length).toBe(2);
  await page.waitForFunction(() => Boolean(window.__fourScene));
  await expect(page.getByTestId('loading-screen')).toContainText(
    `Видео с правилами · 0/${tutorialExamples.length}`,
  );
  await expect(page.locator('[inert]')).toHaveCount(1);
  release();
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  expect(new Set(requests).size).toBe(tutorialExamples.length);
  let unexpected = 0;
  await page.route('**/tutorial/*.mp4', (route) => {
    unexpected++;
    return route.abort();
  });
  await page.getByRole('button', { name: 'Как играть', exact: true }).click();
  for (const example of tutorialExamples) {
    await page
      .getByRole('navigation', { name: 'Примеры правил' })
      .getByRole('button', { name: new RegExp(example.tab) })
      .click();
    await expect(page.locator('video')).toHaveAttribute('src', /^blob:/);
    await expect
      .poll(() =>
        page
          .locator('video')
          .evaluate((v: HTMLVideoElement) => v.currentTime > 0.1 && v.readyState >= 2),
      )
      .toBe(true);
  }
  expect(unexpected).toBe(0);
  await page.reload();
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await page.getByRole('button', { name: 'Как играть', exact: true }).click();
  await expect(page.locator('video')).toHaveAttribute('src', /^blob:/);
  await expect
    .poll(() => page.locator('video').evaluate((v: HTMLVideoElement) => v.currentTime > 0.1))
    .toBe(true);
  expect(unexpected).toBe(0);
});

test('slow optional video downloads can continue after entering the game', async ({ page }) => {
  await page.setViewportSize({ width: 667, height: 375 });
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route('**/tutorial/*.mp4', async (route) => {
    await gate;
    await route.continue();
  });
  try {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await page
      .getByRole('button', { name: 'Продолжить без ожидания видео' })
      .click({ timeout: 12000 });
    await expect(page.getByTestId('loading-screen')).toBeHidden();
    await expect(page.getByRole('button', { name: 'Вдвоём', exact: true })).toBeEnabled();
    release();
    await expect
      .poll(() =>
        page.evaluate(async () => (await (await caches.open('four-tutorial-v1')).keys()).length),
      )
      .toBe(tutorialExamples.length);
  } finally {
    release();
  }
});

test('video preload still works when browser storage is unavailable', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, 'caches', { value: undefined, configurable: true });
  });
  await page.goto('/');
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await page.getByRole('button', { name: 'Как играть', exact: true }).click();
  await expect(page.locator('video')).toHaveAttribute('src', /^blob:/);
  await expect
    .poll(() => page.locator('video').evaluate((v: HTMLVideoElement) => v.currentTime > 0.1))
    .toBe(true);
});

test('slow board download stays behind loading screen, then pieces fall and settle', async ({
  page,
}, testInfo) => {
  const errors = collectErrors(page);
  let release!: () => void;
  const waiting = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route('**/models/four-board.glb', async (route) => {
    await waiting;
    await route.continue();
  });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const loading = page.getByTestId('loading-screen');
  await expect(loading).toBeVisible();
  await page.waitForTimeout(1200);
  await expect(loading).toBeVisible();
  await expect(page.locator('[inert]')).toHaveCount(1);
  await page.screenshot({ path: testInfo.outputPath('loading.png') });
  release();
  await expect(loading).toBeHidden();
  const canvas = page.locator('canvas');
  const before = await canvas.screenshot();
  await page.waitForTimeout(1400);
  const falling = await canvas.screenshot();
  expect(await screenshotDifference(page, before, falling)).toBeGreaterThan(0.005);
  await page.waitForTimeout(2800);
  const settled = await canvas.screenshot();
  await page.waitForTimeout(400);
  expect(await screenshotDifference(page, settled, await canvas.screenshot())).toBeLessThan(0.0001);
  await page.screenshot({ path: testInfo.outputPath('menu-ready.png') });
  expect(errors).toEqual([]);
});

test('failed model download offers a working retry instead of an endless loader', async ({
  page,
}) => {
  await page.route('**/models/four-board.glb', (route) => route.abort());
  await page.goto('/');
  await expect(
    page.getByRole('heading', { name: 'Не удалось загрузить поле', exact: true }),
  ).toBeVisible();
  await page.unroute('**/models/four-board.glb');
  await page.getByRole('button', { name: 'Попробовать снова', exact: true }).click();
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await expect(page.getByRole('button', { name: 'Вдвоём', exact: true })).toBeVisible();
});

test('reduced motion shows the completed board immediately', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  const canvas = page.locator('canvas');
  const before = await canvas.screenshot();
  await page.waitForTimeout(1200);
  expect(await screenshotDifference(page, before, await canvas.screenshot())).toBeLessThan(0.0001);
});
