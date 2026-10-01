import { test, expect } from '@playwright/test';
import { collectErrors, openHistory, place } from './helpers';

test('ranked quick game alerts, survives reload, awards Elo and shows it on another device', async ({
  page,
  browser,
  baseURL,
}, info) => {
  test.setTimeout(60000);
  const other = await browser.newPage({
    baseURL,
    viewport: { width: 320, height: 568 },
    isMobile: true,
    hasTouch: true,
  });
  const username = `Rank${Date.now().toString(36)}`;
  const password = 'rank-browser-test-123';
  const errors = [collectErrors(page), collectErrors(other)];
  try {
    await page.context().grantPermissions(['notifications']);
    await page.addInitScript(() => {
      const log = { notices: [] as string[], tones: 0 };
      (window as unknown as { matchAlerts: typeof log }).matchAlerts = log;
      ServiceWorkerRegistration.prototype.showNotification = async function (title) {
        log.notices.push(title);
      };
      const create = AudioContext.prototype.createOscillator;
      AudioContext.prototype.createOscillator = function () {
        log.tones++;
        return create.call(this);
      };
    });
    for (const [client, name, address] of [
      [page, username, '127.0.1.10'],
      [other, `${username}B`, '127.0.1.11'],
    ] as const) {
      expect(
        (
          await client.request.post('/auth/register', {
            data: { username: name, password },
            headers: { 'x-real-ip': address },
          })
        ).ok(),
      ).toBe(true);
      await client.goto('/');
    }
    await page.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await other.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    await expect(page.getByRole('dialog')).toContainText('Рейтинг соперника: 1000');
    await expect
      .poll(() =>
        page.evaluate(
          () => (window as unknown as { matchAlerts: { notices: string[] } }).matchAlerts.notices,
        ),
      )
      .toEqual(['Соперник найден']);
    expect(
      await page.evaluate(
        () => (window as unknown as { matchAlerts: { tones: number } }).matchAlerts.tones,
      ),
    ).toBeGreaterThanOrEqual(4);
    await expect(page).toHaveTitle(/Соперник найден/);
    await other.waitForTimeout(600);
    const dialog = other.getByRole('dialog');
    expect(await dialog.evaluate((el) => el.scrollHeight <= el.clientHeight + 1)).toBe(true);
    await other.screenshot({ path: info.outputPath('ranked-confirmation-mobile.png') });
    await page.getByRole('button', { name: 'Принять матч', exact: true }).click();
    await expect(page).not.toHaveTitle(/Соперник найден/);
    await other.getByRole('button', { name: 'Принять матч', exact: true }).click();
    await expect(page.getByTestId('ranked-status')).toContainText('1000');
    await page.reload();
    await expect(page.getByTestId('turn-timer')).toHaveText(/\d+сек/);
    await expect(page.getByTestId('ranked-status')).not.toContainText('На ход');
    const timerBefore = Number(
      (await page.getByTestId('turn-timer').innerText()).match(/\d+/)?.[0],
    );
    await page.waitForTimeout(1100);
    const timerAfter = Number((await page.getByTestId('turn-timer').innerText()).match(/\d+/)?.[0]);
    expect(timerAfter).toBeLessThan(timerBefore);
    for (const client of [page, other])
      await client.waitForFunction(() => Boolean(window.__fourScene));
    await page.waitForTimeout(700);
    const first = (await page.getByTestId('turn-status').innerText()).includes('Ваш ход')
      ? page
      : other;
    const second = first === page ? other : page;
    for (const [i, [x, y]] of [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [3, 0],
    ].entries())
      await place(i % 2 ? second : first, x, y, i + 1, (i % 2 ? second : first) === other);
    await expect(first.getByTestId('ranked-result')).toBeVisible();
    await expect(second.getByTestId('ranked-result')).toBeVisible();
    await expect(first.getByTestId('ranked-result')).toContainText('Победа');
    await expect(second.getByTestId('ranked-result')).toContainText('Поражение');
    await expect(first.getByTestId('ranked-result-delta')).toHaveText('+16');
    await expect(second.getByTestId('ranked-result-delta')).toHaveText('-16');
    await expect(first.getByTestId('ranked-result-rating')).toHaveText('1016');
    await expect(second.getByTestId('ranked-result-rating')).toHaveText('984');
    await expect(first.getByTestId('ranked-status')).toContainText('1016 (+16)');
    await expect(second.getByTestId('ranked-status')).toContainText('984 (-16)');
    expect(
      await other.getByTestId('ranked-result').evaluate((el) => {
        const bounds = el.getBoundingClientRect();
        return (
          bounds.top >= 0 &&
          bounds.bottom <= innerHeight &&
          bounds.left >= 0 &&
          bounds.right <= innerWidth &&
          el.scrollHeight <= el.clientHeight + 1
        );
      }),
    ).toBe(true);
    await other.screenshot({ path: info.outputPath('ranked-result-mobile.png') });
    await first.getByRole('button', { name: /Сыграть ещё с/ }).click();
    await expect(first.getByTestId('ranked-result')).toContainText('Ждём решения соперника');
    await second.getByRole('button', { name: /Сыграть ещё с/ }).click();
    for (const client of [page, other])
      await expect(client.getByTestId('turn-timer')).toHaveText(/\d+сек/);
    const before = await (await page.request.get('/auth/history')).json();
    expect(before.rating.games).toBe(1);
    expect(before.matches[0].ratingChange).toBe(first === page ? 16 : -16);
    const third = await browser.newPage({ baseURL });
    try {
      expect((await third.request.post('/auth/login', { data: { username, password } })).ok()).toBe(
        true,
      );
      await third.goto('/');
      await third.getByRole('button', { name: /Аккаунт:/ }).click();
      await expect(third.getByTestId('account-rating')).toContainText(String(before.rating.points));
    } finally {
      await third.close();
    }
    expect(errors.flat()).toEqual([]);
  } finally {
    await other.close();
  }
});

test('ranked surrender keeps the winner result visible and records the loser', async ({
  page,
  browser,
  baseURL,
}) => {
  const other = await browser.newPage({ baseURL });
  try {
    for (const [i, client] of [page, other].entries()) {
      expect(
        (
          await client.request.post('/auth/register', {
            headers: { 'x-real-ip': `127.0.2.${i + 10}` },
            data: {
              username: `Forfeit${Date.now().toString(36)}${i}`,
              password: 'rank-browser-test-123',
            },
          })
        ).ok(),
      ).toBe(true);
      await client.goto('/');
      await client.getByRole('button', { name: 'Рейтинговая игра', exact: true }).click();
    }
    for (const client of [page, other])
      await client.getByRole('button', { name: 'Принять матч', exact: true }).click();
    await page.getByRole('button', { name: 'Покинуть лобби' }).click();
    await expect(page.getByRole('dialog')).toContainText('уменьшит рейтинг');
    await page.getByRole('button', { name: 'Выйти из лобби', exact: true }).click();
    await expect(other.getByTestId('ranked-status')).toContainText('1016 (+16)');
    await expect(other.getByTestId('ranked-status')).toContainText('сдался');
    await openHistory(page);
    await expect(page.getByTestId('history-rating')).toHaveText('984');
    await expect(page.getByRole('dialog')).toContainText('-16 Elo');
    await page.getByRole('button', { name: 'Смотреть', exact: true }).click();
    await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  } finally {
    await other.close();
  }
});
