import { expect, test } from '@playwright/test';
import { collectErrors } from './helpers';

const adminPassword = process.env.ADMIN_E2E_PASSWORD ?? 'control-password-123';

test('administrator finds and edits a player, then creates a temporary password', async ({
  page,
}, info) => {
  const errors = collectErrors(page);
  const username = `AdminCheck${Date.now().toString(36)}`;
  expect(
    (
      await page.request.post('/auth/register', {
        data: { username, password: 'player-password-123' },
      })
    ).ok(),
  ).toBe(true);
  await page.goto('/admin');
  await expect(page.getByRole('heading', { name: 'Администрирование' })).toBeVisible();
  await page.getByLabel('Пароль').fill(adminPassword);
  await page.getByRole('button', { name: 'Войти', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Аккаунты' })).toBeVisible();
  await page.getByLabel('Поиск игроков').fill(username);
  await expect(page.getByRole('button', { name: new RegExp(username) })).toBeVisible();
  await page.getByRole('button', { name: new RegExp(username) }).click();
  await page.getByLabel('Elo').fill('1337');
  await page.getByRole('button', { name: 'Сохранить изменения' }).click();
  await expect(page.getByText('Изменения сохранены.')).toBeVisible();
  await expect(page.getByRole('button', { name: new RegExp(`${username}.*1337`) })).toBeVisible();
  await page.getByRole('button', { name: 'Сбросить пароль' }).click();
  await page.getByRole('button', { name: 'Создать пароль' }).click();
  await expect(page.getByText('Временный пароль показывается один раз')).toBeVisible();
  await page.screenshot({ path: info.outputPath('admin-desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect
    .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1))
    .toBe(true);
  await page.screenshot({ path: info.outputPath('admin-mobile.png'), fullPage: true });
  await page.getByRole('button', { name: 'Удалить аккаунт', exact: true }).click();
  await page.getByLabel('Подтверждение удаления').fill(username);
  await page.screenshot({ path: info.outputPath('admin-delete-confirmation.png'), fullPage: true });
  await page.getByRole('button', { name: 'Удалить безвозвратно' }).click();
  await expect(page.getByText(`Аккаунт ${username} удалён.`)).toBeVisible();
  await expect(page.getByRole('button', { name: new RegExp(username) })).toHaveCount(0);
  expect(errors).toEqual([]);
});
