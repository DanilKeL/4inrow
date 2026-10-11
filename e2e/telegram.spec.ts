import { expect, test } from '@playwright/test';
import { openGame, place } from './helpers';

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true });
test('Telegram fullscreen, safe areas, navigation, moves and minimize work on a phone', async ({
  page,
}) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.addInitScript(() => {
    const events = new Map<string, Set<() => void>>();
    const data = {
      ready: false,
      expanded: false,
      fullscreenRequests: 0,
      backVisible: false,
      confirm: false,
      haptics: 0,
    };
    const button = {
      show: () => {
        data.backVisible = true;
      },
      hide: () => {
        data.backVisible = false;
      },
      onClick: (callback: () => void) => {
        const set = events.get('back') ?? new Set();
        set.add(callback);
        events.set('back', set);
      },
      offClick: (callback: () => void) => {
        events.get('back')?.delete(callback);
      },
    };
    Object.assign(window, {
      __telegramTest: {
        data,
        fire: (name: string) => [...(events.get(name) ?? [])].forEach((callback) => callback()),
      },
      Telegram: {
        WebApp: {
          platform: 'android',
          initData: '',
          viewportStableHeight: 780,
          isFullscreen: false,
          safeAreaInset: { top: 24, bottom: 16, left: 0, right: 0 },
          contentSafeAreaInset: { top: 0, bottom: 0, left: 0, right: 0 },
          ready: () => {
            data.ready = true;
          },
          expand: () => {
            data.expanded = true;
          },
          requestFullscreen() {
            data.fullscreenRequests++;
            this.isFullscreen = true;
            this.viewportStableHeight = 844;
            this.contentSafeAreaInset.top = 48;
            [...(events.get('fullscreenChanged') ?? [])].forEach((callback) => callback());
          },
          isVersionAtLeast: () => true,
          setHeaderColor: () => {},
          setBackgroundColor: () => {},
          setBottomBarColor: () => {},
          disableVerticalSwipes: () => {},
          enableClosingConfirmation: () => {
            data.confirm = true;
          },
          disableClosingConfirmation: () => {
            data.confirm = false;
          },
          onEvent: (name: string, callback: () => void) => {
            const set = events.get(name) ?? new Set();
            set.add(callback);
            events.set(name, set);
          },
          offEvent: (name: string, callback: () => void) => {
            events.get(name)?.delete(callback);
          },
          BackButton: button,
          HapticFeedback: {
            impactOccurred: () => {
              data.haptics++;
            },
            notificationOccurred: () => {},
            selectionChanged: () => {},
          },
        },
      },
    });
  });
  await openGame(page);
  await expect(page.locator('html')).toHaveAttribute('data-telegram', 'true');
  await expect(page.locator('#root')).toHaveCSS('height', '844px');
  expect(
    await page
      .locator('html')
      .evaluate((root) => root.style.getPropertyValue('--safe-area-inset-top')),
  ).toBe('72px');
  const appBounds = await page.locator('#root > div').boundingBox();
  expect(appBounds?.height).toBe(844);
  await place(page, 0, 0, 1, true);
  const state = () =>
    page.evaluate(
      () =>
        (window as unknown as { __telegramTest: { data: Record<string, unknown> } }).__telegramTest
          .data,
    );
  expect(await state()).toMatchObject({
    ready: true,
    expanded: true,
    fullscreenRequests: 1,
    backVisible: true,
    confirm: true,
    haptics: 1,
  });
  await page.evaluate(() =>
    (window as unknown as { __telegramTest: { fire(name: string): void } }).__telegramTest.fire(
      'deactivated',
    ),
  );
  await expect(page.getByRole('dialog', { name: 'Пауза', exact: true })).toBeVisible();
  await page.evaluate(() =>
    (window as unknown as { __telegramTest: { fire(name: string): void } }).__telegramTest.fire(
      'back',
    ),
  );
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.evaluate(() =>
    (window as unknown as { __telegramTest: { fire(name: string): void } }).__telegramTest.fire(
      'back',
    ),
  );
  await expect(page.getByRole('dialog', { name: 'Завершить текущую партию?' })).toBeVisible();
  expect(errors).toEqual([]);
});
