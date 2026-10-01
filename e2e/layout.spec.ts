import { test, expect, type Page } from '@playwright/test';
import { openGame, expectColumnsInsideCanvas, place } from './helpers';

async function withinViewport(page: Page) {
  await expect
    .poll(async () => {
      const bounds = await page.evaluate(() => ({
        scroll: [
          document.documentElement.scrollWidth - innerWidth,
          document.documentElement.scrollHeight - innerHeight,
        ],
        outside: [...document.querySelectorAll('button, input, canvas')]
          .filter((el) => {
            const r = el.getBoundingClientRect();
            return (
              r.width > 0 &&
              r.height > 0 &&
              !el.closest('[aria-hidden="true"]') &&
              (r.left < -1 || r.top < -1 || r.right > innerWidth + 1 || r.bottom > innerHeight + 1)
            );
          })
          .map(
            (el) =>
              el.getAttribute('aria-label') ||
              (el.tagName === 'CANVAS' ? 'canvas' : el.textContent),
          ),
      }));
      return { noScroll: bounds.scroll.every((n) => n <= 1), outside: bounds.outside };
    })
    .toEqual({ noScroll: true, outside: [] });
}
test('desktop and tablet menu and game use one viewport without clipped controls', async ({
  page,
}, info) => {
  test.setTimeout(60000);
  await page.goto('/');
  await page.getByRole('button', { name: 'Вдвоём', exact: true }).waitFor();
  await expect(page.getByRole('button', { name: 'История партий', exact: true })).toHaveCount(0);
  const sizes = [
    [1920, 1080],
    [1366, 768],
    [1280, 600],
    [1024, 768],
    [900, 500],
    [768, 1024],
    [375, 667],
    [320, 568],
  ];
  for (const [width, height] of sizes) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(650);
    await withinViewport(page);
    const heading = page.getByRole('heading', { name: 'Четыре в ряд', exact: true });
    await expect(heading).toBeVisible();
    expect(
      await heading.evaluate((element) => {
        const range = document.createRange();
        range.selectNodeContents(element);
        return range.getClientRects().length === 1 && element.scrollWidth <= element.clientWidth;
      }),
    ).toBe(true);
    if ([1366, 900, 375, 320].includes(width))
      await page.screenshot({ path: info.outputPath(`menu-${width}.png`) });
  }
  await page.setViewportSize({ width: 1366, height: 768 });
  for (const zoom of [0.67, 0.8, 1, 1.25, 1.5, 2]) {
    await page.evaluate((value) => {
      document.documentElement.style.zoom = String(value);
    }, zoom);
    const heading = page.getByRole('heading', { name: 'Четыре в ряд', exact: true });
    expect(
      await heading.evaluate((element) => {
        const range = document.createRange();
        range.selectNodeContents(element);
        return range.getClientRects().length === 1 && element.scrollWidth <= element.clientWidth;
      }),
    ).toBe(true);
    await expect(page.getByRole('heading').filter({ hasText: '3D' })).toHaveCount(0);
  }
  await page.evaluate(() => {
    document.documentElement.style.zoom = '';
  });
  await openGame(page);
  for (const [width, height] of sizes) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(800);
    await withinViewport(page);
    await expectColumnsInsideCanvas(page);
    if (width === 1366 || width === 900)
      await page.screenshot({ path: info.outputPath(`game-${width}.png`) });
  }
  await page.setViewportSize({ width: 1280, height: 600 });
  await page.waitForTimeout(800);
  for (const [i, [x, y]] of [
    [0, 0],
    [0, 4],
    [1, 0],
    [1, 4],
    [2, 0],
    [2, 4],
    [3, 0],
  ].entries())
    await place(page, x, y, i + 1);
  for (const [width, height] of [
    [1280, 600],
    [900, 500],
    [320, 568],
  ]) {
    await page.setViewportSize({ width, height });
    await withinViewport(page);
    await page.getByRole('button', { name: 'Повтор партии', exact: true }).click();
    await withinViewport(page);
    await page.getByRole('button', { name: 'Завершить просмотр', exact: true }).click();
  }
});
