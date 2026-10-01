import { test, expect } from '@playwright/test';

test('mobile search recovers after background disconnect and page reload', async ({
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
      const sockets: WebSocket[] = [];
      const Original = WebSocket;
      window.WebSocket = class extends Original {
        constructor(url: string | URL, protocols?: string | string[]) {
          super(url, protocols);
          sockets.push(this);
        }
      };
      Object.assign(window, {
        suspendSearch: () => {
          Object.defineProperty(document, 'visibilityState', {
            configurable: true,
            value: 'hidden',
          });
          document.dispatchEvent(new Event('visibilitychange'));
          sockets.at(-1)?.close();
        },
        resumeSearch: () => {
          Object.defineProperty(document, 'visibilityState', {
            configurable: true,
            value: 'visible',
          });
          document.dispatchEvent(new Event('visibilitychange'));
        },
        searchSockets: sockets,
      });
    });
    await mobile.goto('/');
    await expect(mobile.getByTestId('loading-screen')).not.toBeVisible();
    await mobile.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    const dialog = mobile.getByRole('dialog', { name: 'Рейтинговая игра' });
    await expect(dialog).toContainText('Ищем соперника');
    const search = await mobile.evaluate(
      () => JSON.parse(sessionStorage.getItem('four-cubed-online-search')!).searchId,
    );
    await mobile.evaluate(() => (window as unknown as { suspendSearch(): void }).suspendSearch());
    await expect(dialog).toContainText('Восстанавливаем поиск');
    await mobile.screenshot({ path: info.outputPath('mobile-search-reconnecting.png') });
    await mobile.evaluate(() => (window as unknown as { resumeSearch(): void }).resumeSearch());
    await expect(dialog).toContainText('Ищем соперника');
    await expect(dialog.getByRole('button', { name: 'Искать снова' })).toHaveCount(0);
    await mobile.reload();
    await expect(dialog).toContainText('Ищем соперника');
    expect(
      await mobile.evaluate(
        () => JSON.parse(sessionStorage.getItem('four-cubed-online-search')!).searchId,
      ),
    ).toBe(search);
    await peer.goto('/');
    await peer.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await expect(dialog).toContainText('Соперник найден');
    await mobile.getByRole('button', { name: 'Принять матч', exact: true }).click();
    await peer.getByRole('button', { name: 'Принять матч', exact: true }).click();
    await expect(mobile.getByTestId('move-count')).toHaveText('0 / 125');
    await expect(peer.getByTestId('move-count')).toHaveText('0 / 125');
    expect(
      await mobile.evaluate(() => sessionStorage.getItem('four-cubed-online-search')),
    ).toBeNull();
  } finally {
    await mobile.close();
    await peer.close();
  }
});

test('cancelling a disconnected search never starts it again on return', async ({
  page,
  browser,
  baseURL,
}) => {
  const peer = await browser.newPage({ baseURL });
  try {
    await page.goto('/');
    await page.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await expect
      .poll(() => page.evaluate(() => Boolean(sessionStorage.getItem('four-cubed-online-search'))))
      .toBe(true);
    await page.context().setOffline(true);
    // A foreground visibility transition probes the stale socket even before the OS reports closure.
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' });
      document.dispatchEvent(new Event('visibilitychange'));
      Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await expect(page.getByRole('dialog')).toContainText('Восстанавливаем поиск');
    await page.getByRole('button', { name: 'Отменить поиск' }).click();
    await page.context().setOffline(false);
    await page.reload();
    await expect(page.getByTestId('loading-screen')).not.toBeVisible();
    await expect(page.getByRole('dialog', { name: 'Рейтинговая игра' })).toHaveCount(0);
    expect(
      await page.evaluate(() => sessionStorage.getItem('four-cubed-online-search')),
    ).toBeNull();
    await peer.goto('/');
    await peer.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await expect(peer.getByRole('dialog')).toContainText('Ищем соперника');
    await peer.getByRole('button', { name: 'Отменить поиск' }).click();
  } finally {
    await page.context().setOffline(false);
    await peer.close();
  }
});
