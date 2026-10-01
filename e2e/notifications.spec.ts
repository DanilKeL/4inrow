import { test, expect } from '@playwright/test';

test('mobile match notification waits for permission and uses the service worker', async ({
  browser,
  baseURL,
}, info) => {
  const mobile = await browser.newPage({
    baseURL,
    viewport: { width: 320, height: 568 },
    isMobile: true,
    hasTouch: true,
  });
  const peer = await browser.newPage({ baseURL });
  try {
    await mobile.addInitScript(() => {
      const state = { notices: [] as string[], tones: 0, grant: () => {} };
      Object.assign(window, { notificationTest: state });
      let permission = 'default';
      Object.defineProperty(window, 'Notification', {
        configurable: true,
        value: class {
          static get permission() {
            return permission;
          }
          static requestPermission() {
            return new Promise((resolve) => {
              state.grant = () => {
                permission = 'granted';
                resolve(permission);
              };
            });
          }
          constructor() {
            throw new TypeError('Mobile browsers require showNotification');
          }
        },
      });
      ServiceWorkerRegistration.prototype.showNotification = async function (title) {
        state.notices.push(title);
      };
      const create = AudioContext.prototype.createOscillator;
      AudioContext.prototype.createOscillator = function () {
        state.tones++;
        return create.call(this);
      };
    });
    await mobile.goto('/');
    await peer.goto('/');
    await expect(mobile.getByTestId('loading-screen')).not.toBeVisible();
    await expect(peer.getByTestId('loading-screen')).not.toBeVisible();
    await mobile.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await expect(mobile.getByRole('dialog')).toContainText('Ищем соперника');
    await peer.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await expect(mobile.getByRole('dialog')).toContainText('Соперник найден');
    await mobile.evaluate(() =>
      (window as unknown as { notificationTest: { grant(): void } }).notificationTest.grant(),
    );
    await expect
      .poll(() =>
        mobile.evaluate(
          () =>
            (window as unknown as { notificationTest: { notices: string[] } }).notificationTest
              .notices,
        ),
      )
      .toEqual(['Соперник найден']);
    expect(
      await mobile.evaluate(
        () => (window as unknown as { notificationTest: { tones: number } }).notificationTest.tones,
      ),
    ).toBeGreaterThanOrEqual(4);
    await mobile.screenshot({ path: info.outputPath('mobile-match-found.png') });
    await mobile.getByRole('button', { name: 'Принять матч', exact: true }).click();
    await peer.getByRole('button', { name: 'Принять матч', exact: true }).click();
    await expect(mobile.getByTestId('move-count')).toHaveText('0 / 125');
  } finally {
    await mobile.close();
    await peer.close();
  }
});

for (const platform of ['iphone', 'blocked'] as const) {
  test(`mobile search fits the screen without notification guidance: ${platform}`, async ({
    browser,
    baseURL,
  }, info) => {
    const page = await browser.newPage({
      baseURL,
      viewport: { width: 320, height: 568 },
      isMobile: true,
      hasTouch: true,
      ...(platform === 'iphone'
        ? {
            userAgent:
              'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile Safari/604.1',
          }
        : {}),
    });
    try {
      await page.addInitScript(() => {
        Object.defineProperty(window, 'Notification', {
          configurable: true,
          value: class {
            static permission = 'denied';
          },
        });
      });
      await page.goto('/');
      await expect(page.getByTestId('loading-screen')).not.toBeVisible();
      await page.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
      const dialog = page.getByRole('dialog');
      await expect(dialog).toContainText('Ищем соперника');
      await expect(dialog).not.toContainText(/уведомлен|экран Домой/i);
      expect(
        await dialog.evaluate((el) => {
          const r = el.getBoundingClientRect();
          return el.scrollHeight <= el.clientHeight + 1 && r.top >= 0 && r.bottom <= innerHeight;
        }),
      ).toBe(true);
      await page.screenshot({ path: info.outputPath(`notification-help-${platform}.png`) });
      const manifest = await (await page.request.get('/manifest.json')).json();
      expect(manifest.display).toBe('standalone');
      for (const icon of manifest.icons)
        expect((await page.request.get(icon.src)).headers()['content-type']).toContain('image/png');
      await page.getByRole('button', { name: 'Отменить поиск' }).click();
    } finally {
      await page.close();
    }
  });
}
