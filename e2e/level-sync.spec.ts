import { test, expect } from '@playwright/test';

test('migrates local level records to the account and restores them in a fresh browser', async ({
  page,
  browser,
}) => {
  const username = `Levels_${Date.now()}`;
  const password = 'level-password-123';
  const registration = await page.request.post('/auth/register', { data: { username, password } });
  expect(registration.ok()).toBe(true);
  await page.addInitScript(() => {
    if (!localStorage.getItem('four-cubed-levels-v1'))
      localStorage.setItem(
        'four-cubed-levels-v1',
        JSON.stringify({ version: 1, state: { best: { 1: 5, 2: 3 } } }),
      );
  });
  await page.goto('/');
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await page.getByRole('button', { name: 'Уровни', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Уровень 1', exact: true })).toContainText('5');
  await expect
    .poll(async () => (await (await page.request.get('/auth/levels')).json()).best)
    .toEqual({ 1: 5, 2: 3 });
  const second = await browser.newContext({ viewport: { width: 390, height: 844 } });
  try {
    expect(
      (
        await second.request.post('http://127.0.0.1:5173/auth/login', {
          data: { username, password },
        })
      ).ok(),
    ).toBe(true);
    const mobile = await second.newPage();
    await mobile.goto('http://127.0.0.1:5173/');
    await expect(mobile.getByTestId('loading-screen')).toBeHidden();
    await mobile.getByRole('button', { name: 'Уровни', exact: true }).click();
    await expect(mobile.getByRole('button', { name: 'Уровень 2', exact: true })).toContainText('3');
    await expect(mobile.getByTestId('levels')).toContainText('2 / 40 пройдено');
    await second.request.post('http://127.0.0.1:5173/auth/levels', {
      data: { owner: username, best: { 1: 2 } },
    });
    await page.reload();
    await expect(page.getByTestId('loading-screen')).toBeHidden();
    await page.getByRole('button', { name: 'Уровни', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Уровень 1', exact: true })).toContainText('2');
  } finally {
    await second.close();
  }
});
