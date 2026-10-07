import { test, expect, type Page } from '@playwright/test';

async function clearHeader(page: Page, safeTop: number) {
  const bounds = await page.locator('header').evaluate((header) => {
    const rect = header.getBoundingClientRect();
    return {
      top: rect.top,
      position: getComputedStyle(header).position,
      buttons: [...header.querySelectorAll('button')].map((button) => {
        const r = button.getBoundingClientRect();
        return { top: r.top, bottom: r.bottom, left: r.left, right: r.right };
      }),
      width: innerWidth,
      height: innerHeight,
      scroll: document.documentElement.scrollHeight - innerHeight,
    };
  });
  expect(bounds.top).toBe(0);
  expect(bounds.position).toBe('sticky');
  expect(bounds.scroll).toBeLessThanOrEqual(1);
  for (const button of bounds.buttons) {
    expect(button.top).toBeGreaterThanOrEqual(safeTop);
    expect(button.bottom).toBeLessThanOrEqual(bounds.height);
    expect(button.left).toBeGreaterThanOrEqual(0);
    expect(button.right).toBeLessThanOrEqual(bounds.width);
  }
  const strip = await page.locator('#status-bar-background').boundingBox();
  expect(strip?.y).toBe(0);
  expect(strip?.height).toBe(Math.max(1, safeTop));
}

test('home-screen iPhone pins the painted header at the top and keeps notch controls accessible', async ({
  browser,
  baseURL,
}, info) => {
  test.setTimeout(60000);
  // Exercise navigator.standalone: real home-screen UAs may omit Version/Safari.
  // The native iOS scroll-edge compositor itself requires an actual iPhone.
  const context = await browser.newContext({
    baseURL,
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
  });
  try {
    await context.addInitScript(() => {
      Object.defineProperty(navigator, 'standalone', { value: true });
    });
    const page = await context.newPage();
    await page.goto('/');
    await page.evaluate(() => {
      document.documentElement.style.setProperty('--safe-area-inset-top', '59px');
      document.documentElement.style.setProperty('--safe-area-inset-bottom', '34px');
    });
    await expect(page.locator('html')).toHaveAttribute('data-ios-standalone', '');
    await expect(page.getByTestId('loading-screen')).toBeHidden();
    await clearHeader(page, 59);
    await page.screenshot({ path: info.outputPath('iphone-standalone-menu.png') });
    await page.getByRole('button', { name: 'Настройки', exact: true }).click();
    await expect(page.getByRole('dialog', { name: 'Настройки' })).toBeVisible();
    await page.getByRole('button', { name: 'Закрыть', exact: true }).click();
    await clearHeader(page, 59);
    await page.getByRole('button', { name: 'Вдвоём', exact: true }).click();
    await page.getByRole('button', { name: 'Начать игру', exact: true }).click();
    await page.getByRole('button', { name: /Начать/ }).click();
    await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
    await clearHeader(page, 59);
    await page.setViewportSize({ width: 844, height: 390 });
    await page.evaluate(() => {
      document.documentElement.style.setProperty('--safe-area-inset-top', '0px');
      document.documentElement.style.setProperty('--safe-area-inset-bottom', '21px');
    });
    await clearHeader(page, 0);
    await page.screenshot({ path: info.outputPath('iphone-standalone-landscape.png') });
  } finally {
    await context.close();
  }
});
