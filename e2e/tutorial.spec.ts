import { test, expect } from '@playwright/test';
import { tutorialExamples } from '../src/ui/tutorialExamples';

async function progressSamples(page: import('@playwright/test').Page) {
  return page.getByRole('slider', { name: 'Позиция ролика' }).evaluate(async (slider) => {
    const values: number[] = [];
    for (let index = 0; index < 36; index++) {
      values.push(Number((slider as HTMLInputElement).value));
      await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
    }
    return values;
  });
}

test('the video progress moves smoothly from the beginning on desktop and mobile', async ({
  page,
}) => {
  for (const viewport of [
    { width: 1366, height: 768 },
    { width: 390, height: 844 },
  ]) {
    await page.setViewportSize(viewport);
    await page.goto('/');
    await page.getByRole('button', { name: 'Как играть', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Как играть' });
    const video = dialog.locator('video');
    await expect
      .poll(() => video.evaluate((item: HTMLVideoElement) => item.currentTime > 0))
      .toBe(true);
    await dialog.getByRole('button', { name: 'Повторить пример' }).click();
    const samples = await progressSamples(page);
    const distinct = new Set(samples.map((value) => value.toFixed(3)));
    expect(distinct.size).toBeGreaterThan(8);
    expect(samples[0]).toBeLessThan(1);
    expect(samples.at(-1)).toBeGreaterThan(samples[0]);
    const state = await dialog
      .getByRole('slider', { name: 'Позиция ролика' })
      .evaluate((slider) => ({
        current: Number((slider as HTMLInputElement).value),
        maximum: Number((slider as HTMLInputElement).max),
        fill: getComputedStyle(slider).getPropertyValue('--video-progress'),
      }));
    expect(state.current).toBeLessThan(state.maximum - 1);
    expect(state.fill).toMatch(/%/);
    await dialog.getByRole('button', { name: 'Понятно', exact: true }).click();
  }
});

test('real game clips play, seek and replay; all examples fit desktop and small phones', async ({
  page,
}, info) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Как играть', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Как играть' });
  for (const example of tutorialExamples) {
    await dialog.getByRole('button', { name: new RegExp(example.tab) }).click();
    await expect(dialog.getByRole('heading', { name: example.title })).toBeVisible();
    const video = dialog.locator('video');
    await expect
      .poll(() =>
        video.evaluate((v: HTMLVideoElement) => ({
          error: v.error?.message,
          ready: v.readyState >= 2,
          advancing: v.currentTime > 0.1,
          finite: Number.isFinite(v.duration) && v.duration > 5,
        })),
      )
      .toEqual({ error: undefined, ready: true, advancing: true, finite: true });
    await dialog.getByRole('button', { name: 'Остановить пример' }).click();
    await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(true);
    await dialog.getByRole('slider', { name: 'Позиция ролика' }).fill('4');
    await expect
      .poll(() => video.evaluate((v: HTMLVideoElement) => Math.abs(v.currentTime - 4) < 0.3))
      .toBe(true);
    await dialog.getByRole('button', { name: 'Повторить пример' }).click();
    await expect
      .poll(() => video.evaluate((v: HTMLVideoElement) => !v.paused && v.currentTime < 2))
      .toBe(true);
  }
  // Use the final position to review framing and the longest explanation.
  const video = dialog.locator('video');
  await video.evaluate((v: HTMLVideoElement) => {
    v.pause();
    v.currentTime = v.duration - 0.2;
  });
  for (const [width, height] of [
    [1366, 768],
    [900, 500],
    [320, 568],
    [390, 844],
    [667, 375],
  ]) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(250);
    const layout = await dialog.evaluate((el) => ({
      overflow: el.scrollHeight > el.clientHeight + 1,
      outside: [...el.querySelectorAll('button, input, video, h3, p')]
        .filter((item) => {
          const r = item.getBoundingClientRect();
          return (
            r.width > 0 &&
            r.height > 0 &&
            (r.left < 0 || r.right > innerWidth || r.top < 0 || r.bottom > innerHeight)
          );
        })
        .map((item) => item.textContent),
    }));
    expect(layout).toEqual({ overflow: false, outside: [] });
    await page.screenshot({ path: info.outputPath(`guide-${width}.png`) });
  }
  await dialog.getByRole('button', { name: 'Понятно', exact: true }).click();
  await expect(dialog).not.toBeVisible();
});

test('reduced motion shows the poster until the user plays; failed video has a useful image', async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.route('**/tutorial/horizontal.mp4', (route) => route.abort());
  await page.goto('/');
  await page.getByRole('button', { name: 'Как играть', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Как играть' });
  await expect(dialog.locator('video')).toHaveAttribute('preload', 'none');
  expect(await dialog.locator('video').evaluate((v: HTMLVideoElement) => v.paused)).toBe(true);
  await dialog.getByRole('button', { name: 'Воспроизвести пример' }).click();
  await expect
    .poll(() => dialog.locator('video').evaluate((v: HTMLVideoElement) => v.currentTime > 0.1))
    .toBe(true);
  await dialog.getByRole('button', { name: /Горизонталь/ }).click();
  await dialog.getByRole('button', { name: 'Воспроизвести пример' }).click();
  await expect(dialog.getByRole('img', { name: 'Четыре на одном уровне' })).toBeVisible();
  await expect(dialog.getByText('Видео недоступно. Показан итоговый пример.')).toBeVisible();
});
