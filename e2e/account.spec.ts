import { test, expect } from '@playwright/test';

test('registration, unique username, login, logout and online identity', async ({
  page,
  browser,
  baseURL,
}, info) => {
  const username = `Player_${Date.now().toString(36)}`;
  const password = 'unique-test-pass-123';
  const newPassword = 'changed-test-pass-456';
  await page.goto('/');
  await expect(page.getByRole('button', { name: /^Аккаунт: Гость_\d{6}$/ })).toBeVisible();
  await page.getByRole('button', { name: /Аккаунт:/ }).click();
  const account = page.getByRole('dialog', { name: 'Личный кабинет' });
  await account.getByLabel('Имя пользователя').fill('Русский');
  await account.getByLabel('Email').fill(`${Date.now()}@example.test`);
  await account.getByLabel('Пароль').fill(password);
  expect(
    await account
      .getByLabel('Имя пользователя')
      .evaluate((input: HTMLInputElement) => input.validity.patternMismatch),
  ).toBe(true);
  await expect(account.getByText(/Английские буквы, цифры/)).toBeVisible();
  await account.getByLabel('Имя пользователя').fill(username);
  await account.getByLabel('Email').fill(`${Date.now()}@example.test`);
  await account.getByLabel('Пароль').fill(password);
  await account.getByRole('button', { name: 'Зарегистрироваться' }).click();
  await expect(account.getByTestId('account-dashboard')).toBeVisible();
  await expect(account.getByTestId('account-rating')).toContainText('1000');
  await expect(account.getByTestId('account-total')).toHaveText('0');
  await page.screenshot({ path: info.outputPath('account-overview-desktop.png') });
  for (const viewport of [
    { width: 320, height: 568 },
    { width: 390, height: 844 },
  ]) {
    await page.setViewportSize(viewport);
    expect(await account.evaluate((el) => el.scrollHeight <= el.clientHeight + 1)).toBe(true);
  }
  await page.screenshot({ path: info.outputPath('account-overview-mobile.png') });
  await account.getByRole('button', { name: 'Безопасность' }).click();
  await account.getByLabel('Текущий пароль').fill('wrong-password');
  await account.getByLabel(/^Новый пароль/).fill(newPassword);
  await account.getByLabel('Повторите новый пароль').fill(newPassword);
  for (const viewport of [
    { width: 320, height: 568 },
    { width: 390, height: 844 },
  ]) {
    await page.setViewportSize(viewport);
    expect(await account.evaluate((el) => el.scrollHeight <= el.clientHeight + 1)).toBe(true);
  }
  await page.screenshot({ path: info.outputPath('account-security-mobile.png') });
  await account.getByRole('button', { name: 'Изменить пароль' }).click();
  await expect(account.getByRole('alert')).toContainText('Текущий пароль неверен');
  await account.getByLabel('Текущий пароль').fill(password);
  await account.getByRole('button', { name: 'Изменить пароль' }).click();
  await expect(account.getByRole('status')).toContainText('Остальные сеансы завершены');
  await account.getByRole('button', { name: 'Закрыть' }).click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.reload();
  await expect(page.getByRole('button', { name: `Аккаунт: ${username}` })).toBeVisible();
  await page.getByRole('button', { name: 'Онлайн', exact: true }).click();
  await page.getByRole('button', { name: 'Создать лобби', exact: true }).click();
  await expect(page.getByTestId('lobby-code')).toHaveText(/^[A-Z]{5}$/);
  await expect(page.getByRole('button', { name: `Аккаунт: ${username}` })).toBeVisible();

  const other = await browser.newPage({ baseURL });
  try {
    await other.goto('/');
    await other.getByRole('button', { name: /Аккаунт:/ }).click();
    const otherAccount = other.getByRole('dialog', { name: 'Личный кабинет' });
    await otherAccount.getByLabel('Имя пользователя').fill(username.toUpperCase());
    await otherAccount.getByLabel('Email').fill(`${Date.now()}-other@example.test`);
    await otherAccount.getByLabel('Пароль').fill('other-test-pass-123');
    await otherAccount.getByRole('button', { name: 'Зарегистрироваться' }).click();
    await expect(otherAccount.getByRole('alert')).toContainText('уже занято');
    await otherAccount.getByRole('button', { name: 'Вход' }).click();
    await otherAccount.getByLabel('Пароль').fill('wrong-pass-123');
    await otherAccount.getByRole('button', { name: 'Войти', exact: true }).click();
    await expect(otherAccount.getByRole('alert')).toContainText('Неверное');
    await otherAccount.getByLabel('Пароль').fill(password);
    await otherAccount.getByRole('button', { name: 'Войти', exact: true }).click();
    await expect(otherAccount.getByRole('alert')).toContainText('Неверное');
    await otherAccount.getByLabel('Пароль').fill(newPassword);
    await otherAccount.getByRole('button', { name: 'Войти', exact: true }).click();
    await expect(otherAccount.getByText(username)).toBeVisible();
    await otherAccount.getByRole('button', { name: 'Выйти из аккаунта' }).click();
    await expect(otherAccount.getByText(/Гость_\d{6}/)).toBeVisible();
  } finally {
    await other.close();
  }
});
