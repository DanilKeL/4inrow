import { test, expect } from '@playwright/test';
import {
  collectErrors,
  expectColumnsInsideCanvas,
  openGame,
  openHistory,
  place,
  screenshotDifference,
} from './helpers';
import type { Page } from '@playwright/test';
import { replay, serialize } from '../src/game/core';

async function fitsScreen(page: Page) {
  const layout = await page.evaluate(() => ({
    width: innerWidth,
    height: innerHeight,
    scrollWidth: document.documentElement.scrollWidth,
    scrollHeight: document.documentElement.scrollHeight,
    dialogs: [...document.querySelectorAll<HTMLElement>('[role="dialog"]')].map((el) => ({
      client: el.clientHeight,
      scroll: el.scrollHeight,
    })),
    lobbyOverflow: (() => {
      const heading = document.querySelector('[data-testid="lobby-code"]')?.parentElement;
      if (!heading) return false;
      const bounds = heading.getBoundingClientRect();
      return [...heading.children].some((el) => {
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && (rect.left < bounds.left - 1 || rect.right > bounds.right + 1);
      });
    })(),
    outside: [...document.querySelectorAll<HTMLElement>('button, input, canvas')]
      .filter((el) => {
        const rect = el.getBoundingClientRect();
        if (!rect.width || !rect.height || el.closest('[aria-hidden="true"]')) return false;
        return (
          rect.left < -1 ||
          rect.right > innerWidth + 1 ||
          rect.top < -1 ||
          rect.bottom > innerHeight + 1
        );
      })
      .map((el) => el.getAttribute('aria-label') || el.textContent),
  }));
  expect(layout.scrollWidth).toBeLessThanOrEqual(layout.width + 1);
  expect(layout.scrollHeight).toBeLessThanOrEqual(layout.height + 1);
  expect(layout.outside).toEqual([]);
  expect(layout.lobbyOverflow).toBe(false);
  for (const dialog of layout.dialogs) expect(dialog.scroll).toBeLessThanOrEqual(dialog.client + 1);
}

async function registerLongName(page: Page) {
  await page.getByRole('button', { name: /Аккаунт:/ }).click();
  const account = page.getByRole('dialog', { name: 'Личный кабинет' });
  await account.getByLabel('Имя пользователя').fill(`ExtraWidePlayer${Date.now().toString(36)}`);
  await account.getByLabel('Email').fill(`${Date.now()}@example.test`);
  await account.getByLabel('Пароль').fill('mobile-test-pass-123');
  await account.getByRole('button', { name: 'Зарегистрироваться' }).click();
  await expect(account.getByTestId('account-dashboard')).toBeVisible();
  await account.getByRole('button', { name: 'Закрыть' }).click();
}

for (const [width, height] of [
  [320, 568],
  [375, 667],
  [390, 844],
  [430, 932],
  [667, 375],
  [844, 390],
]) {
  test(`${width}x${height} menu, setup, settings and tutorial fit without scrolling`, async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width, height });
    await page.goto('/');
    await page.getByRole('button', { name: 'Вдвоём', exact: true }).waitFor();
    await fitsScreen(page);
    await page.getByRole('button', { name: 'Вдвоём', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await page.waitForTimeout(250);
    for (const mode of [/Вдвоём/, /Против AI/, /Онлайн/]) {
      await dialog.getByRole('button', { name: mode }).click();
      await fitsScreen(page);
      const overflow = await dialog
        .locator('button strong, button small')
        .evaluateAll((els) =>
          els.filter((el) => el.scrollWidth > el.clientWidth + 1).map((el) => el.textContent),
        );
      expect(overflow).toEqual([]);
    }
    await page.screenshot({ path: testInfo.outputPath('setup.png') });
    await dialog.getByRole('button', { name: 'Закрыть', exact: true }).click();
    await page.getByRole('button', { name: 'Настройки', exact: true }).click();
    await page.waitForTimeout(250);
    await fitsScreen(page);
    await dialog.getByRole('button', { name: 'Закрыть', exact: true }).click();
    await page.getByRole('button', { name: 'Как играть', exact: true }).click();
    await page.waitForTimeout(250);
    await fitsScreen(page);
    await page.screenshot({ path: testInfo.outputPath('tutorial.png') });
  });
}

test('quick match confirmation fits a small phone without scrolling', async ({
  page,
  browser,
  baseURL,
}) => {
  await page.setViewportSize({ width: 320, height: 568 });
  const other = await browser.newPage({ baseURL, viewport: { width: 390, height: 844 } });
  try {
    await page.goto('/');
    await other.goto('/');
    await page.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await fitsScreen(page);
    await other.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Принять матч' })).toBeVisible();
    await fitsScreen(page);
    await page.getByRole('button', { name: 'Отказаться' }).click();
    await expect(page.getByRole('dialog', { name: 'Рейтинговая игра' })).not.toBeVisible();
    await expect(other.getByRole('dialog', { name: 'Рейтинговая игра' })).toContainText(
      'Ищем соперника',
    );
  } finally {
    await other.close();
  }
});

test('history pages, renaming and replay fit a small phone', async ({ page }, testInfo) => {
  const owner = `Mobile${Date.now().toString(36)}`;
  expect(
    (
      await page.request.post('/auth/register', {
        data: { username: owner, password: 'mobile-test-pass-123' },
      })
    ).ok(),
  ).toBe(true);
  const game = replay(
    [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [4, 2],
      [3, 4],
    ].map(([x, y]) => ({ x, y })),
  );
  const matches = Array.from({ length: 4 }, (_, i) => ({
    id: `local-test-${i}`,
    owner,
    title: 'Партия с длинным названием для проверки',
    names: ['Первый игрок', 'Второй игрок'],
    game: serialize(game),
    mode: 'local',
    date: Date.now(),
    elapsed: 40,
  }));
  for (const data of matches) {
    expect((await page.request.post('/auth/history', { data })).ok()).toBe(true);
    expect(
      (
        await page.request.post('/auth/history/rename', {
          data: { owner, id: data.id, title: data.title },
        })
      ).ok(),
    ).toBe(true);
  }
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/');
  await openHistory(page);
  await expect(page.getByTestId('stats-total')).toHaveText('4');
  await fitsScreen(page);
  await page.screenshot({ path: testInfo.outputPath('statistics-mobile.png') });
  await page.setViewportSize({ width: 667, height: 375 });
  await fitsScreen(page);
  await page.screenshot({ path: testInfo.outputPath('statistics-landscape.png') });
  await page.setViewportSize({ width: 320, height: 568 });
  await page.getByRole('button', { name: 'Название', exact: true }).first().click();
  await fitsScreen(page);
  await page.getByRole('button', { name: 'Сохранить', exact: true }).click();
  await page.getByRole('button', { name: 'Дальше', exact: true }).click();
  await page.getByRole('button', { name: 'Смотреть', exact: true }).first().click();
  await fitsScreen(page);
  await expect(page.getByRole('button', { name: 'Разбор партии', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'В начало повтора' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  await fitsScreen(page);
  await page.screenshot({ path: testInfo.outputPath('history-mobile.png') });
});

test('390px portrait supports real touch placement without horizontal overflow', async ({
  page,
}, testInfo) => {
  const errors = collectErrors(page);
  await openGame(page);
  await place(page, 2, 2, 1, true);
  await place(page, 1, 2, 2, true);
  await fitsScreen(page);
  const width = await page.evaluate(() => ({
    client: document.documentElement.clientWidth,
    scroll: document.documentElement.scrollWidth,
  }));
  expect(width.scroll).toBeLessThanOrEqual(width.client);
  await page.screenshot({ path: testInfo.outputPath('mobile-game.png'), fullPage: true });
  await page.getByRole('button', { name: 'Пауза', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Пауза' })).toBeVisible();
  await page.getByRole('button', { name: 'Продолжить', exact: true }).click();
  await expect(page.getByTestId('move-count')).toHaveText('2 / 125');
  expect(errors).toEqual([]);
});

test('phone sizes and landscape retain all columns including a five-piece tower', async ({
  page,
}) => {
  const errors = collectErrors(page);
  await openGame(page);
  for (let count = 1; count <= 5; count++) await place(page, 2, 2, count, true);
  for (const [width, height] of [
    [390, 844],
    [320, 568],
    [393, 852],
    [430, 932],
    [844, 390],
  ]) {
    await page.setViewportSize({ width, height });
    await page.getByRole('button', { name: 'Сбросить вид' }).click();
    await page.waitForTimeout(900);
    await expectColumnsInsideCanvas(page);
    await fitsScreen(page);
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.getByRole('button', { name: 'Сверху', exact: true }).click();
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.waitForTimeout(900);
    await expectColumnsInsideCanvas(page);
  }
  expect(errors).toEqual([]);
});

test('touch rotation leaves the board clickable after release', async ({ page }) => {
  await openGame(page);
  const before = await page.evaluate(() => window.__fourScene!.getColumnScreenPositions()[12]);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', {
    type: 'touchStart',
    touchPoints: [{ x: before.screenX, y: before.screenY }],
  });
  for (let step = 1; step <= 8; step++) {
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: [{ x: before.screenX + step * 8, y: before.screenY + step * 3 }],
    });
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  await place(page, 1, 1, 1, true);
});

test('long names, victory and replay remain on screen on small phones and landscape', async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/');
  await registerLongName(page);
  await page.getByRole('button', { name: 'Вдвоём', exact: true }).click();
  await page.getByRole('button', { name: 'Начать игру', exact: true }).click();
  await page.getByRole('button', { name: /Начать/ }).click();
  await page.waitForFunction(() => Boolean(window.__fourScene));
  await page.waitForTimeout(800);
  await fitsScreen(page);
  for (const [i, [x, y]] of [
    [0, 0],
    [0, 4],
    [1, 0],
    [1, 4],
    [2, 0],
    [2, 4],
    [3, 0],
  ].entries())
    await place(page, x, y, i + 1, true);
  for (const [width, height] of [
    [320, 568],
    [667, 375],
  ]) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(800);
    await fitsScreen(page);
    await page.screenshot({ path: testInfo.outputPath(`win-${width}.png`) });
    await page.getByRole('button', { name: 'Повтор партии', exact: true }).click();
    await fitsScreen(page);
    await page.getByRole('button', { name: 'В начало повтора' }).click();
    await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
    await page.getByRole('button', { name: 'Следующий ход' }).click();
    await expect(page.getByTestId('move-count')).toHaveText('1 / 125');
    await page.getByRole('button', { name: 'Завершить просмотр' }).click();
  }
});

test('online lobby and long player names fit without scrolling', async ({
  page,
  browser,
}, testInfo) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/');
  await registerLongName(page);
  await page.getByRole('button', { name: 'Онлайн', exact: true }).click();
  await page.getByRole('button', { name: 'Создать лобби', exact: true }).click();
  await page.getByTestId('lobby-code').waitFor();
  await fitsScreen(page);
  const code = await page.getByTestId('lobby-code').innerText();
  const guest = await browser.newPage();
  try {
    await guest.goto('http://127.0.0.1:5173');
    await guest.getByRole('button', { name: 'Онлайн', exact: true }).click();
    await guest.getByLabel('Код лобби', { exact: true }).fill(code);
    await guest.getByRole('button', { name: 'Войти в лобби', exact: true }).click();
    await page.getByTestId('turn-status').filter({ hasText: 'Ваш ход' }).waitFor();
    await place(page, 2, 2, 1, true);
    for (const [width, height] of [
      [320, 568],
      [390, 664],
      [844, 390],
    ]) {
      await page.setViewportSize({ width, height });
      await page.waitForTimeout(800);
      await fitsScreen(page);
      await page.getByRole('button', { name: 'Вид', exact: true }).click();
      await fitsScreen(page);
      await page.getByRole('button', { name: 'Вид', exact: true }).click();
      await page.screenshot({ path: testInfo.outputPath(`online-${width}.png`) });
    }
  } finally {
    await guest.close();
  }
});

test('touch dialogs avoid close-button focus and view supports disjoint layers', async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/');
  await page.getByRole('button', { name: 'Вдвоём', exact: true }).tap();
  const dialog = page.getByRole('dialog', { name: 'Новая игра' });
  await expect(dialog).toBeFocused();
  await expect(dialog.getByRole('button', { name: 'Закрыть', exact: true })).not.toBeFocused();
  await page.screenshot({ path: testInfo.outputPath('setup-no-focus-ring.png') });
  await dialog.getByRole('button', { name: 'Закрыть', exact: true }).tap();
  await openGame(page);
  await page.getByRole('button', { name: 'Настройки', exact: true }).tap();
  await page.getByRole('switch', { name: 'Анимации' }).uncheck();
  await page.getByRole('switch', { name: 'Предпросмотр хода' }).uncheck();
  await page.getByRole('slider', { name: 'Громкость звуков' }).fill('42');
  await fitsScreen(page);
  await page.screenshot({ path: testInfo.outputPath('volume-mobile.png') });
  await page.getByRole('button', { name: 'Закрыть', exact: true }).tap();
  for (let count = 1; count <= 5; count++) await place(page, 2, 2, count, true);
  await page.getByRole('button', { name: 'Вид', exact: true }).tap();
  for (const layer of [1, 3])
    await page.getByRole('button', { name: 'Слой ' + layer, exact: true }).tap();
  await fitsScreen(page);
  await page.screenshot({ path: testInfo.outputPath('layers-245-menu.png') });
  await page.getByRole('button', { name: 'Закрыть меню вида' }).tap();
  await page.waitForTimeout(300);
  const first = await page
    .locator('canvas')
    .screenshot({ path: testInfo.outputPath('layers-245.png') });
  await page.getByRole('button', { name: 'Вид', exact: true }).tap();
  for (const layer of [1, 2, 3, 4, 5]) {
    const button = page.getByRole('button', { name: 'Слой ' + layer, exact: true });
    await expect(button).toHaveAttribute('aria-pressed', String([2, 4, 5].includes(layer)));
    await button.tap();
  }
  await page.getByRole('button', { name: 'Закрыть меню вида' }).tap();
  await page.waitForTimeout(300);
  const second = await page
    .locator('canvas')
    .screenshot({ path: testInfo.outputPath('layers-13.png') });
  expect(await screenshotDifference(page, first, second)).toBeGreaterThan(0.001);
  await page.getByRole('button', { name: 'Вид', exact: true }).tap();
  for (const layer of [1, 2, 3, 4, 5])
    await expect(page.getByRole('button', { name: 'Слой ' + layer, exact: true })).toHaveAttribute(
      'aria-pressed',
      String([1, 3].includes(layer)),
    );
  await page.getByRole('button', { name: 'Все слои', exact: true }).tap();
  await page.getByRole('button', { name: 'Закрыть меню вида' }).tap();
  await place(page, 1, 2, 6, true);
});
