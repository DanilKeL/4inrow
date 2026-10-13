import { expect, test, devices } from '@playwright/test';
import { openGame, place } from './helpers';

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true });

test('iPhone Mini App suppresses game selection while login fields remain editable', async ({
  browser,
  baseURL,
}) => {
  const phone = devices['iPhone 13'];
  const context = await browser.newContext({
    viewport: phone.viewport,
    userAgent: phone.userAgent,
    deviceScaleFactor: phone.deviceScaleFactor,
    isMobile: true,
    hasTouch: true,
    baseURL,
  });
  const page = await context.newPage();
  try {
    await page.addInitScript(() => {
      const noop = () => {};
      window.Telegram = {
        WebApp: {
          platform: 'ios',
          initData: '',
          viewportStableHeight: 844,
          isVersionAtLeast: () => false,
          ready: noop,
          expand: noop,
          setHeaderColor: noop,
          setBackgroundColor: noop,
          enableClosingConfirmation: noop,
          disableClosingConfirmation: noop,
          onEvent: noop,
          offEvent: noop,
          BackButton: { show: noop, hide: noop, onClick: noop, offClick: noop },
        },
      };
    });
    await page.goto('/');
    await expect(page.getByTestId('loading-screen')).toBeHidden();
    await expect(page.locator('html')).toHaveAttribute('data-telegram', 'true');
    const heading = page.getByRole('heading', { name: 'Четыре в ряд', exact: true });
    await expect(heading).toHaveCSS('user-select', 'none');
    await expect(page.locator('html')).toHaveCSS('touch-action', 'manipulation');
    await expect(page.locator('body')).toHaveCSS('touch-action', 'manipulation');
    const point = await heading.boundingBox();
    for (let tap = 0; tap < 2; tap++)
      await page.touchscreen.tap(point!.x + point!.width / 2, point!.y + point!.height / 2);
    expect(await page.evaluate(() => getSelection()?.toString())).toBe('');
    expect(await page.evaluate(() => visualViewport?.scale)).toBe(1);
    expect(
      await heading.evaluate((element) => {
        const event = new Event('selectstart', { cancelable: true, bubbles: true });
        element.dispatchEvent(event);
        return event.defaultPrevented;
      }),
    ).toBe(true);
    await page.getByRole('button', { name: /Аккаунт:/ }).click();
    const account = page.getByRole('dialog', { name: 'Личный кабинет', exact: true });
    await account.getByRole('button', { name: 'Вход', exact: true }).click();
    const username = account.getByLabel('Имя пользователя');
    await expect(username).toHaveCSS('user-select', 'text');
    await username.fill('TouchPlayer');
    await username.selectText();
    expect(
      await username.evaluate((element: HTMLInputElement) => [
        element.selectionStart,
        element.selectionEnd,
      ]),
    ).toEqual([0, 11]);
    expect(
      await username.evaluate((element) => {
        const event = new Event('contextmenu', { cancelable: true, bubbles: true });
        element.dispatchEvent(event);
        return event.defaultPrevented;
      }),
    ).toBe(false);
    await account.getByRole('button', { name: 'Закрыть', exact: true }).click();
    await page.evaluate(() => document.documentElement.removeAttribute('data-telegram'));
    await expect(heading).not.toHaveCSS('user-select', 'none');
  } finally {
    await context.close();
  }
});
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
  await page.getByRole('button', { name: /Аккаунт:/ }).click();
  const account = page.getByRole('dialog', { name: 'Личный кабинет' });
  await account.getByRole('button', { name: 'Вход', exact: true }).click();
  await account.getByLabel('Имя пользователя').fill('KeepThisTab');
  await page.evaluate(() =>
    (window as unknown as { __telegramTest: { fire(name: string): void } }).__telegramTest.fire(
      'deactivated',
    ),
  );
  await expect(account).toBeVisible();
  await expect(account.getByLabel('Имя пользователя')).toHaveValue('KeepThisTab');
  await expect(account.getByRole('button', { name: 'Войти', exact: true })).toBeVisible();
  await account.getByRole('button', { name: 'Закрыть' }).click();
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
