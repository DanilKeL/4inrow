import { test, expect, type Page } from '@playwright/test';
import { collectErrors, columnPosition, place } from './helpers';

test.describe('online lobbies', () => {
  test.setTimeout(60_000);

  test('quick game waits for both confirmations before opening a shared board', async ({
    page,
    browser,
    baseURL,
  }) => {
    const other = await browser.newPage({ baseURL, viewport: { width: 1440, height: 1000 } });
    try {
      await page.goto('/');
      await other.goto('/');
      await page.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
      await expect(page.getByRole('dialog', { name: 'Рейтинговая игра' })).toContainText(
        'Ищем соперника',
      );
      await other.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
      const firstOffer = page.getByRole('dialog', { name: 'Рейтинговая игра' });
      const secondOffer = other.getByRole('dialog', { name: 'Рейтинговая игра' });
      await expect(firstOffer).toContainText('Соперник найден');
      await expect(secondOffer).toContainText('Соперник найден');
      await firstOffer.getByRole('button', { name: 'Принять матч' }).click();
      await expect(firstOffer).toContainText('Ждём подтверждения соперника');
      await expect(page.getByTestId('move-count')).toHaveCount(0);
      await secondOffer.getByRole('button', { name: 'Принять матч' }).click();
      await expect(firstOffer).not.toBeVisible();
      await expect(secondOffer).not.toBeVisible();
      await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
      await expect(other.getByTestId('move-count')).toHaveText('0 / 125');
      await expect(page.getByText('РЕЙТИНГОВАЯ ИГРА')).toBeVisible();
      await expect(page.getByTestId('lobby-code')).toHaveCount(0);
    } finally {
      await other.close();
    }
  });

  async function openOnline(page: Page) {
    await page.goto('/');
    await page.getByRole('button', { name: 'Онлайн', exact: true }).click();
    const setup = page.getByRole('dialog', { name: 'Новая игра' });
    await expect(setup).toBeVisible();
    return setup;
  }

  async function createLobby(page: Page) {
    const setup = await openOnline(page);
    await setup.getByRole('button', { name: 'Создать лобби', exact: true }).click();
    await expect(setup).not.toBeVisible();
    const code = page.getByTestId('lobby-code');
    await expect(code).toHaveText(/^[A-Z]{5}$/);
    await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
    return (await code.innerText()).trim();
  }

  async function joinLobby(page: Page, code: string) {
    const setup = await openOnline(page);
    await setup.getByRole('textbox', { name: 'Код лобби', exact: true }).fill(code.toLowerCase());
    await setup.getByRole('button', { name: 'Войти в лобби', exact: true }).click();
    await expect(setup).not.toBeVisible();
    await expect(page.getByTestId('lobby-code')).toHaveText(code);
  }

  async function ready(page: Page) {
    await page.waitForFunction(() => Boolean(window.__fourScene));
    // Let the initial camera and any incoming piece animation settle before a real canvas click.
    await page.waitForTimeout(600);
  }

  test('agreed pause lasts two minutes, survives reload and resumes both boards', async ({
    page,
    browser,
    baseURL,
  }, info) => {
    test.setTimeout(165000);
    const other = await browser.newPage({
      baseURL,
      viewport: { width: 320, height: 568 },
      isMobile: true,
      hasTouch: true,
    });
    const errors = collectErrors(page);
    const otherErrors = collectErrors(other);
    try {
      const code = await createLobby(page);
      await joinLobby(other, code);
      await ready(page);
      await page.getByRole('button', { name: 'Пауза', exact: true }).click();
      await page.getByRole('button', { name: 'Предложить паузу · 2 мин' }).click();
      await expect(page.getByRole('dialog', { name: 'Запрос паузы' })).toContainText(
        'Ждём согласия',
      );
      await other.getByRole('button', { name: 'Принять паузу', exact: true }).click();
      for (const client of [page, other]) {
        await expect(client.getByRole('dialog', { name: 'Пауза · 2 минуты' })).toBeVisible();
        await expect(client.getByTestId('turn-status')).toHaveText('Пауза');
      }
      await other.screenshot({ path: info.outputPath('pause-mobile.png') });
      const outside = await other.locator('[role="dialog"]').evaluate((el) => {
        const r = el.getBoundingClientRect();
        return r.left < 0 || r.top < 0 || r.right > innerWidth || r.bottom > innerHeight;
      });
      expect(outside).toBe(false);
      await page.getByRole('button', { name: 'Закрыть', exact: true }).click();
      const point = await columnPosition(page, 0, 0);
      await page.mouse.click(point.screenX, point.screenY);
      await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
      await page.reload();
      await expect(page.getByRole('dialog', { name: 'Пауза · 2 минуты' })).toBeVisible();
      await expect(page.getByTestId('pause-countdown')).toHaveText(/0[12]:\d\d/);
      await expect(page.getByRole('dialog', { name: 'Пауза · 2 минуты' })).not.toBeVisible({
        timeout: 125000,
      });
      await expect(other.getByRole('dialog', { name: 'Пауза · 2 минуты' })).not.toBeVisible();
      await ready(page);
      await place(page, 0, 0, 1);
      await expect(other.getByTestId('move-count')).toHaveText('1 / 125');
      await page.getByRole('button', { name: 'Пауза', exact: true }).click();
      await expect(page.getByRole('button', { name: 'Пауза использована' })).toBeDisabled();
      expect(errors).toEqual([]);
      expect(otherErrors).toEqual([]);
    } finally {
      await other.close();
    }
  });

  test('both ready resumes early and preserves readiness after reload on mobile', async ({
    page,
    browser,
    baseURL,
  }, info) => {
    const other = await browser.newPage({
      baseURL,
      viewport: { width: 320, height: 568 },
      isMobile: true,
      hasTouch: true,
    });
    try {
      const code = await createLobby(page);
      await joinLobby(other, code);
      await page.getByRole('button', { name: 'Пауза', exact: true }).click();
      await page.getByRole('button', { name: 'Предложить паузу · 2 мин' }).click();
      await other.getByRole('button', { name: 'Принять паузу', exact: true }).click();
      await page.getByRole('button', { name: 'Готов', exact: true }).click();
      await expect(page.getByRole('button', { name: 'Вы готовы', exact: true })).toBeDisabled();
      await expect(other.getByRole('dialog').getByRole('status')).toContainText('Соперник готов.');
      await other.screenshot({ path: info.outputPath('pause-ready-mobile.png') });
      expect(
        await other.getByRole('dialog').evaluate((el) => {
          const r = el.getBoundingClientRect();
          return r.left >= 0 && r.top >= 0 && r.right <= innerWidth && r.bottom <= innerHeight;
        }),
      ).toBe(true);
      await page.reload();
      await expect(page.getByRole('button', { name: 'Вы готовы', exact: true })).toBeDisabled();
      await other.getByRole('button', { name: 'Готов', exact: true }).click();
      for (const client of [page, other])
        await expect(client.getByRole('dialog', { name: 'Пауза · 2 минуты' })).not.toBeVisible();
      await ready(page);
      await place(page, 0, 0, 1);
      await expect(other.getByTestId('move-count')).toHaveText('1 / 125');
      await page.getByRole('button', { name: 'Пауза', exact: true }).click();
      await expect(page.getByRole('button', { name: 'Пауза использована' })).toBeDisabled();
    } finally {
      await other.close();
    }
  });

  test('opponent can decline a pause and continue playing', async ({ page, browser, baseURL }) => {
    const other = await browser.newPage({ baseURL });
    try {
      const code = await createLobby(page);
      await joinLobby(other, code);
      await ready(page);
      await page.getByRole('button', { name: 'Пауза', exact: true }).click();
      await page.getByRole('button', { name: 'Предложить паузу · 2 мин' }).click();
      await other.getByRole('button', { name: 'Отклонить', exact: true }).click();
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(other.getByRole('dialog')).toHaveCount(0);
      await place(page, 0, 0, 1);
      await expect(other.getByTestId('move-count')).toHaveText('1 / 125');
    } finally {
      await other.close();
    }
  });

  test('leaving during a pause closes the peer countdown', async ({ page, browser, baseURL }) => {
    const other = await browser.newPage({ baseURL });
    try {
      const code = await createLobby(page);
      await joinLobby(other, code);
      await page.getByRole('button', { name: 'Пауза', exact: true }).click();
      await page.getByRole('button', { name: 'Предложить паузу · 2 мин' }).click();
      await other.getByRole('button', { name: 'Принять паузу', exact: true }).click();
      await expect(other.getByTestId('pause-countdown')).toHaveText(/^(02:00|01:\d\d)$/);
      await page.getByRole('button', { name: 'Закрыть', exact: true }).click();
      await page.getByRole('button', { name: 'Покинуть лобби', exact: true }).click();
      await page.getByRole('button', { name: 'Выйти из лобби', exact: true }).click();
      await expect(other.getByRole('dialog', { name: 'Пауза · 2 минуты' })).not.toBeVisible();
      await expect(other.getByRole('alert')).toContainText('Игрок покинул лобби');
    } finally {
      await other.close();
    }
  });

  test('copy button puts the lobby code in the clipboard without the secure API', async ({
    page,
    context,
    baseURL,
  }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: baseURL });
    const code = await createLobby(page);
    await page.evaluate(() => {
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined });
    });
    await page.getByRole('button', { name: 'Скопировать код лобби' }).click();
    await expect(page.getByText('Код скопирован', { exact: true })).toBeVisible();
    const copied = await page.evaluate(async () => {
      delete (navigator as unknown as Record<string, unknown>).clipboard;
      return navigator.clipboard.readText();
    });
    expect(copied).toBe(code);
  });

  test('two browsers alternate real board moves, share a win and agree to a rematch', async ({
    page: host,
    browser,
    baseURL,
  }) => {
    const guest = await browser.newPage({ baseURL, viewport: { width: 1440, height: 1000 } });
    const errors = [collectErrors(host), collectErrors(guest)];
    try {
      const code = await createLobby(host);
      await ready(host);
      const waitingColumn = await columnPosition(host, 2, 2);
      await host.mouse.click(waitingColumn.screenX, waitingColumn.screenY);
      await expect(host.getByTestId('move-count')).toHaveText('0 / 125');

      await joinLobby(guest, code);
      await expect(host.getByTestId('turn-status')).toContainText('Ваш ход');
      await expect(guest.getByTestId('turn-status')).toContainText('Ход соперника');
      await expect(host.getByTestId('turn-timer')).toHaveText('—сек');
      await expect(guest.getByTestId('turn-timer')).toHaveText('—сек');
      await ready(guest);

      const wrongTurnColumn = await columnPosition(guest, 2, 2);
      await guest.mouse.click(wrongTurnColumn.screenX, wrongTurnColumn.screenY);
      await guest.waitForTimeout(300);
      await expect(guest.getByTestId('move-count')).toHaveText('0 / 125');
      await expect(host.getByTestId('move-count')).toHaveText('0 / 125');

      const moves = [
        [0, 0],
        [0, 1],
        [1, 0],
        [1, 1],
        [2, 0],
        [2, 1],
        [3, 0],
      ];
      for (const [index, [x, y]] of moves.entries()) {
        const current = index % 2 === 0 ? host : guest;
        const other = index % 2 === 0 ? guest : host;
        await expect(current.getByTestId('turn-status')).toContainText('Ваш ход');
        await place(current, x, y, index + 1);
        await expect(other.getByTestId('move-count')).toHaveText(`${index + 1} / 125`);
      }
      for (const player of [host, guest]) {
        await expect(player.getByRole('heading', { name: /Победа: Гость_\d{6}/ })).toBeVisible();
      }
      await host.getByRole('button', { name: 'Ещё партия', exact: true }).click();
      await expect(host.getByText('Ждём согласия соперника', { exact: true })).toBeVisible();
      await expect(guest.getByTestId('move-count')).toHaveText('7 / 125');
      await guest.getByRole('button', { name: 'Ещё партия', exact: true }).click();
      for (const player of [host, guest]) {
        await expect(player.getByTestId('move-count')).toHaveText('0 / 125');
        await expect(player.getByTestId('lobby-code')).toHaveText(code);
        await expect(player.getByRole('heading', { name: /Победа:/ })).toHaveCount(0);
      }
      await expect(guest.getByTestId('turn-status')).toContainText('Ваш ход');
      await expect(host.getByTestId('turn-status')).toContainText('Ход соперника');
      await ready(guest);
      await place(guest, 2, 2, 1);
      await expect(host.getByTestId('move-count')).toHaveText('1 / 125');
      expect(errors.flat()).toEqual([]);
    } finally {
      await guest.close();
    }
  });

  test('reload resumes the same seat and moves; leaving ends the peer lobby', async ({
    page: host,
    browser,
    baseURL,
  }) => {
    const guest = await browser.newPage({ baseURL, viewport: { width: 1440, height: 1000 } });
    const errors = [collectErrors(host), collectErrors(guest)];
    try {
      const code = await createLobby(host);
      await joinLobby(guest, code);
      await expect(host.getByTestId('turn-status')).toContainText('Ваш ход');
      await ready(host);
      await place(host, 2, 2, 1);
      await expect(guest.getByTestId('move-count')).toHaveText('1 / 125');
      await guest.reload();
      await expect(guest.getByTestId('lobby-code')).toHaveText(code);
      await expect(guest.getByTestId('move-count')).toHaveText('1 / 125');
      await expect(guest.getByTestId('turn-status')).toContainText('Ваш ход');
      await expect(host.getByTestId('turn-status')).toContainText('Ход соперника');
      await ready(guest);
      await place(guest, 2, 2, 2);
      await expect(host.getByTestId('move-count')).toHaveText('2 / 125');

      await guest.getByRole('button', { name: 'Покинуть лобби', exact: true }).click();
      await guest
        .getByRole('dialog', { name: 'Выйти из лобби?' })
        .getByRole('button', { name: 'Выйти из лобби', exact: true })
        .click();
      await expect(guest.getByRole('button', { name: 'Вдвоём', exact: true })).toBeVisible();
      await expect(host.getByText(/покинул лобби/)).toBeVisible();
      const point = await columnPosition(host, 3, 3);
      await host.mouse.click(point.screenX, point.screenY);
      await host.waitForTimeout(300);
      await expect(host.getByTestId('move-count')).toHaveText('2 / 125');
      expect(errors.flat()).toEqual([]);
    } finally {
      await guest.close();
    }
  });

  test('lobby codes accept lowercase, reject incomplete input, and report full or missing rooms', async ({
    page: host,
    browser,
    baseURL,
  }) => {
    const guest = await browser.newPage({ baseURL, viewport: { width: 1440, height: 1000 } });
    const third = await browser.newPage({ baseURL, viewport: { width: 1440, height: 1000 } });
    try {
      const code = await createLobby(host);
      await joinLobby(guest, code);
      const setup = await openOnline(third);
      const input = setup.getByRole('textbox', { name: 'Код лобби', exact: true });
      const join = setup.getByRole('button', { name: 'Войти в лобби', exact: true });
      await input.fill('abc');
      await expect(join).toBeDisabled();
      await input.fill(code.toLowerCase());
      await join.click();
      await expect(setup.getByRole('alert')).toContainText(/уже два игрока|заполнено/);
      await input.fill(code === 'QQQQQ' ? 'ZZZZZ' : 'QQQQQ');
      await join.click();
      await expect(setup.getByRole('alert')).toContainText(/не найдено/);
      await expect(host.getByTestId('move-count')).toHaveText('0 / 125');
      await expect(guest.getByTestId('move-count')).toHaveText('0 / 125');
    } finally {
      await guest.close();
      await third.close();
    }
  });
});
