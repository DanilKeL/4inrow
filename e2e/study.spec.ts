import { test, expect } from '@playwright/test';
import { collectErrors, openGame, openHistory, place } from './helpers';

test('finished matches keep replay and history without analysis; history survives reload and supports rename/delete', async ({
  page,
  browser,
  baseURL,
}, testInfo) => {
  const errors = collectErrors(page);
  const username = `History${Date.now().toString(36)}`;
  const password = 'history-test-pass-123';
  expect((await page.request.post('/auth/register', { data: { username, password } })).ok()).toBe(
    true,
  );
  await openGame(page);
  const moves = [
    [0, 0],
    [0, 4],
    [1, 0],
    [1, 4],
    [2, 0],
    [2, 4],
    [4, 2],
    [3, 4],
  ];
  for (const [i, [x, y]] of moves.entries()) await place(page, x, y, i + 1);
  await expect(page.getByRole('button', { name: 'Разбор партии', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Повтор партии', exact: true }).click();
  await page.getByRole('button', { name: 'В начало повтора' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  await page.getByRole('button', { name: 'Следующий ход' }).click();
  await expect(page.getByTestId('move-count')).toHaveText('1 / 125');
  await page.screenshot({ path: testInfo.outputPath('history-replay.png') });
  await page.getByRole('button', { name: 'Завершить просмотр' }).click();
  await page.getByRole('button', { name: 'Главное меню', exact: true }).click();
  await openHistory(page);
  await expect(page.getByTestId('stats-total')).toHaveText('1');
  await expect(page.getByTestId('stats-losses')).toHaveText('1');
  await page.getByRole('button', { name: 'Название', exact: true }).click();
  await page.getByRole('textbox', { name: 'Название партии' }).fill('Моя первая партия');
  await page.getByRole('button', { name: 'Сохранить', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Название', exact: true })).toBeEnabled();
  const other = await browser.newPage({ baseURL });
  try {
    await other.goto('/');
    expect((await other.request.post('/auth/login', { data: { username, password } })).ok()).toBe(
      true,
    );
    await other.reload();
    await openHistory(other);
    await expect(other.getByRole('dialog')).toContainText('Моя первая партия');
    await expect(other.getByTestId('stats-losses')).toHaveText('1');
  } finally {
    await other.close();
  }
  await page.reload();
  await openHistory(page);
  await expect(page.getByRole('dialog')).toContainText('Моя первая партия');
  await page.getByRole('button', { name: 'Смотреть', exact: true }).click();
  await expect(page.getByTestId('move-count')).toHaveText('8 / 125');
  await expect(page.getByRole('button', { name: 'Разбор партии', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Завершить просмотр' }).click();
  await openHistory(page);
  await page.getByRole('button', { name: 'Удалить партию Моя первая партия' }).click();
  await expect(page.getByRole('dialog')).toContainText('Сыграйте партию до конца');
  await expect(page.getByTestId('stats-total')).toHaveText('1');
  expect(errors).toEqual([]);
});
