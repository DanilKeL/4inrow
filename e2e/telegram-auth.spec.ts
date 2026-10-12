import { expect, test, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { createHmac } from 'node:crypto';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';

const botToken = '8834741855:isolated-browser-test';
let pair: Awaited<ReturnType<typeof generateKeyPair>>;
let server: ChildProcess;
let api: string;
let emails: { email: string; token: string; purpose?: string }[];
test.beforeAll(async () => {
  pair = await generateKeyPair('RS256');
});
test.beforeEach(async ({ page }, info) => {
  emails = [];
  server = spawn(process.execPath, ['--import', 'tsx', 'e2e/telegram-auth-server.ts'], {
    env: {
      ...process.env,
      FOUR_TEST_MAIL: info.title.includes('email binding') ? '1' : '0',
      FOUR_TEST_TELEGRAM_JWKS: JSON.stringify({
        keys: [{ ...(await exportJWK(pair.publicKey)), kid: 'e2e', alg: 'RS256' }],
      }),
    },
    stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
    windowsHide: true,
  });
  server.on('message', (message) => {
    if ((message as { type?: string }).type === 'mail')
      emails.push(message as (typeof emails)[number]);
  });
  api = await new Promise<string>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Telegram test server did not start')), 10000);
    server.stdout!.on('data', (chunk) => {
      const url = /http:\/\/127\.0\.0\.1:\d+/.exec(chunk.toString());
      if (url) {
        clearTimeout(timer);
        resolve(url[0]);
      }
    });
    server.once('error', reject);
    server.once('exit', (code) => {
      clearTimeout(timer);
      reject(new Error(`Telegram test server exited: ${code}`));
    });
  });
  await page.route('**/auth/**', async (route) => {
    const url = new URL(route.request().url());
    const response = await route.fetch({ url: `${api}${url.pathname}${url.search}` });
    await route.fulfill({ response });
  });
  // The external SDK UI is mocked; its token is signed and verified by the real server.
  await page.route('https://telegram.org/js/telegram-login.js', (route) =>
    route.fulfill({
      contentType: 'application/javascript',
      body: `
    window.Telegram = window.Telegram || {};
    window.Telegram.Login = {auth(options, callback) {window.__telegramAuth = {options, callback};}};
  `,
    }),
  );
});

test('Telegram recovery and email binding are usable on a small phone and keep the same account', async ({
  page,
}, info) => {
  await page.setViewportSize({ width: 320, height: 568 });
  const account = await openAccount(page);
  const button = account.getByRole('button', { name: 'Войти через Telegram' });
  await expect(button).toBeEnabled();
  await button.click();
  await finishLogin(page, 444444444, 'EmailPlayer');
  await account.getByRole('button', { name: 'Завершить регистрацию' }).click();
  await expect(account.getByTestId('account-dashboard')).toBeVisible();
  const response = await fetch(`${api}/auth/telegram/bot-reset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${botToken}` },
    body: JSON.stringify({ id: '444444444' }),
  });
  const { token } = (await response.json()) as { token: string };
  // A recovery link must open the reset form even when this browser is already signed in.
  await page.goto(`/?reset=${token}`);
  await expect(page.locator('[aria-busy="true"]')).toHaveCount(0);
  await account.getByLabel('Новый пароль', { exact: true }).fill('recovered-password-123');
  await account.getByLabel('Повторите пароль').fill('recovered-password-123');
  await account.getByRole('button', { name: 'Изменить пароль' }).click();
  await expect(account.getByTestId('account-dashboard')).toBeVisible();
  await account.getByRole('button', { name: 'Безопасность' }).click();
  await account.getByRole('button', { name: 'Привязать почту' }).click();
  await account.getByLabel('Email', { exact: true }).fill('player@example.org');
  await account.getByRole('button', { name: 'Отправить подтверждение' }).click();
  await expect(account.getByRole('status')).toContainText('Подтвердите привязку');
  await expect.poll(() => emails.length).toBe(1);
  expect(emails[0]).toMatchObject({ email: 'player@example.org', purpose: 'binding' });
  expect(
    await account.evaluate((element) => element.scrollHeight <= element.clientHeight + 1),
  ).toBe(true);
  await page.screenshot({ path: info.outputPath('telegram-email-binding-mobile.png') });
  const proof = await page.evaluate(
    (token) =>
      fetch('/auth/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token }),
      }).then((r) => r.json()),
    emails[0].token,
  );
  expect(proof).toMatchObject({ username: 'EmailPlayer', emailVerified: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.reload();
  await account.getByRole('button', { name: 'Обзор' }).click();
  await expect(account.getByText('player@example.org')).toBeVisible();
});
test.afterEach(async () => {
  if (server && server.exitCode === null)
    await new Promise<void>((resolve) => {
      server.once('exit', () => resolve());
      server.kill();
    });
});
async function finishLogin(page: Page, id: number, username: string) {
  const nonce = await page.evaluate(
    () =>
      (window as unknown as { __telegramAuth: { options: { nonce: string } } }).__telegramAuth
        .options.nonce,
  );
  const token = await new SignJWT({ id, preferred_username: username, nonce })
    .setProtectedHeader({ alg: 'RS256', kid: 'e2e' })
    .setIssuer('https://oauth.telegram.org')
    .setAudience('8834741855')
    .setSubject(`sub-${id}`)
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(pair.privateKey);
  await page.evaluate(
    (token) =>
      (
        window as unknown as { __telegramAuth: { callback: (data: { id_token: string }) => void } }
      ).__telegramAuth.callback({ id_token: token }),
    token,
  );
}
async function openAccount(page: Page) {
  await page.goto('/');
  await page.getByRole('button', { name: /Аккаунт:/ }).click();
  return page.getByRole('dialog', { name: 'Личный кабинет' });
}

test('Telegram button is visible before its configuration arrives without moving the form', async ({
  page,
}) => {
  let release!: () => void;
  const waiting = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route('**/auth/telegram/config', async (route) => {
    await waiting;
    await route.fulfill({ json: { clientId: '8834741855', miniApp: true } });
  });
  const account = await openAccount(page);
  const button = account.getByRole('button', { name: 'Войти через Telegram' });
  await expect(button).toBeVisible();
  await expect(button).toBeDisabled();
  const input = account.getByLabel('Имя пользователя');
  const before = (await input.boundingBox())!.y - (await account.boundingBox())!.y;
  release();
  await expect(button).toBeEnabled();
  const after = (await input.boundingBox())!.y - (await account.boundingBox())!.y;
  expect(after).toBeCloseTo(before, 0);
});

test('Profile removes duplicate controls and keeps the security tab when returning to a phone browser', async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const account = await openAccount(page);
  await account.getByRole('button', { name: 'Войти через Telegram' }).click();
  await finishLogin(page, 555444333, 'CleanProfile');
  await account.getByRole('button', { name: 'Завершить регистрацию' }).click();
  await expect(account.getByTestId('account-dashboard')).toBeVisible();
  await expect(account.getByText('Telegram', { exact: true })).toHaveCount(0);
  await expect(account.getByRole('button', { name: 'Привязать почту' })).toHaveCount(0);
  await expect(account.getByText('Недавняя форма')).toHaveCount(0);
  await expect(account.getByRole('button', { name: 'История', exact: true })).toHaveCount(0);
  await expect(account.getByRole('button', { name: 'Вся история' })).toBeVisible();
  await account.getByRole('button', { name: 'Безопасность' }).click();
  await account.getByRole('button', { name: 'Привязать почту' }).click();
  await account.getByLabel('Email', { exact: true }).fill('draft@example.org');
  // Headless Chromium keeps every page visible, so deliver the mobile lifecycle explicitly.
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: true });
    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' });
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('blur'));
  });
  await page.evaluate(() => {
    Reflect.deleteProperty(document, 'hidden');
    Reflect.deleteProperty(document, 'visibilityState');
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('focus'));
  });
  await expect(account).toBeVisible();
  await expect(account.getByLabel('Email', { exact: true })).toHaveValue('draft@example.org');
  // Reload simulates the OS discarding a background page. Restore navigation only.
  await page.reload();
  await expect(account).toBeVisible();
  await expect(account.getByRole('button', { name: 'Безопасность' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(account.getByRole('button', { name: 'Привязать почту' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(account.getByLabel('Email', { exact: true })).toHaveValue('');
  await account.getByRole('button', { name: 'Обзор' }).click();
  await account.getByRole('button', { name: 'Вся история' }).click();
  await expect(page.getByRole('dialog', { name: 'История партий' })).toBeVisible();
});

test('Telegram creates a playable account, survives reload, and permits an optional password', async ({
  page,
}, info) => {
  const account = await openAccount(page);
  const button = account.getByRole('button', { name: 'Войти через Telegram' });
  await expect(button).toBeEnabled();
  for (const viewport of [
    { width: 320, height: 568 },
    { width: 390, height: 844 },
    { width: 1440, height: 1000 },
  ]) {
    await page.setViewportSize(viewport);
    await expect(button).toBeVisible();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
    expect(
      await account.evaluate((element) => element.scrollHeight <= element.clientHeight + 1),
    ).toBe(true);
  }
  await page.screenshot({ path: info.outputPath('telegram-registration-desktop.png') });
  await button.click();
  await finishLogin(page, 111111111, 'TelegramBrowser');
  await expect(account.getByLabel('Имя пользователя')).toHaveValue('TelegramBrowser');
  await account.getByLabel('Имя пользователя').fill('ChosenBrowser');
  await page.setViewportSize({ width: 320, height: 568 });
  expect(
    await account.evaluate((element) => element.scrollHeight <= element.clientHeight + 1),
  ).toBe(true);
  await page.screenshot({ path: info.outputPath('telegram-choose-username-mobile.png') });
  await account.getByRole('button', { name: 'Завершить регистрацию' }).click();
  await expect(account.getByTestId('account-dashboard')).toBeVisible();
  await expect(account.getByTestId('account-rating')).toContainText('1000');
  await account.getByRole('button', { name: 'Безопасность' }).click();
  await expect(account.getByLabel('Текущий пароль')).toHaveCount(0);
  await expect(account.getByText('Telegram · @TelegramBrowser')).toBeVisible();
  await account.getByLabel(/^Новый пароль/).fill('telegram-password-123');
  await account.getByLabel('Повторите новый пароль').fill('telegram-password-123');
  await account.getByRole('button', { name: 'Создать пароль' }).click();
  await expect(account.getByLabel('Текущий пароль')).toBeVisible();
  await page.reload();
  await expect(page.getByRole('button', { name: 'Аккаунт: ChosenBrowser' })).toBeVisible();
  await account.getByRole('button', { name: 'Обзор' }).click();
  await account.getByRole('button', { name: 'Выйти' }).click();
  await expect(account.getByRole('button', { name: 'Войти через Telegram' })).toBeEnabled();
  await account.getByRole('button', { name: 'Войти через Telegram' }).click();
  await finishLogin(page, 111111111, 'ChangedTelegramName');
  await expect(page.getByRole('button', { name: 'Аккаунт: ChosenBrowser' })).toBeVisible();
});

test('linking Telegram retains the existing nickname and level records', async ({ page }) => {
  const response = await fetch(`${api}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'OriginalPlayer', password: 'password-123' }),
  });
  const cookie = response.headers.getSetCookie()[0].split(';')[0];
  await fetch(`${api}/auth/levels`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Cookie: cookie },
    body: JSON.stringify({ owner: 'OriginalPlayer', best: { '1': 4 } }),
  });
  await page.context().addCookies([
    {
      name: 'four_session',
      value: cookie.split('=')[1],
      domain: '127.0.0.1',
      path: '/',
      httpOnly: true,
    },
  ]);
  const account = await openAccount(page);
  await account.getByRole('button', { name: 'Безопасность' }).click();
  const link = account.getByRole('button', { name: 'Привязать Telegram' });
  await expect(link).toBeEnabled();
  await link.click();
  await finishLogin(page, 222222222, 'DifferentName');
  await expect(account.getByText('Telegram · @DifferentName')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Аккаунт: OriginalPlayer' })).toBeVisible();
  await expect(account.getByLabel('Текущий пароль')).toBeVisible();
  const progress = await page.evaluate(() => fetch('/auth/levels').then((r) => r.json()));
  expect(progress.best['1']).toBe(4);
});

test('an invalid Telegram token keeps the player a guest and shows a recoverable error', async ({
  page,
}) => {
  const account = await openAccount(page);
  const button = account.getByRole('button', { name: 'Войти через Telegram' });
  await expect(button).toBeEnabled();
  await button.click();
  await page.evaluate(() =>
    (
      window as unknown as { __telegramAuth: { callback: (data: { id_token: string }) => void } }
    ).__telegramAuth.callback({ id_token: 'forged.token.signature' }),
  );
  await expect(account.getByRole('alert')).toContainText('Не удалось подтвердить');
  await expect(button).toBeEnabled();
  await expect(page.getByRole('button', { name: /^Аккаунт: Гость_/ })).toBeVisible();
});

test('inside a Telegram Mini App the signed identity logs in without a browser popup', async ({
  page,
}) => {
  const data = new URLSearchParams({
    auth_date: String(Math.floor(Date.now() / 1000)),
    user: JSON.stringify({ id: 333333333, first_name: 'Игрок', username: 'MiniAppPlayer' }),
  });
  const check = [...data]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');
  data.set(
    'hash',
    createHmac('sha256', createHmac('sha256', 'WebAppData').update(botToken).digest())
      .update(check)
      .digest('hex'),
  );
  await page.addInitScript((initData) => {
    const noop = () => {};
    Object.assign(window, {
      Telegram: {
        WebApp: {
          platform: 'ios',
          initData,
          viewportStableHeight: 844,
          isFullscreen: true,
          isVersionAtLeast: () => true,
          ready: noop,
          expand: noop,
          setHeaderColor: noop,
          setBackgroundColor: noop,
          setBottomBarColor: noop,
          disableVerticalSwipes: noop,
          enableClosingConfirmation: noop,
          disableClosingConfirmation: noop,
          onEvent: noop,
          offEvent: noop,
          BackButton: { show: noop, hide: noop, onClick: noop, offClick: noop },
        },
      },
    });
  }, data.toString());
  await page.setViewportSize({ width: 390, height: 844 });
  const account = await openAccount(page);
  await expect(account.getByRole('button', { name: 'Войти через Telegram' })).toBeEnabled();
  await account.getByRole('button', { name: 'Войти через Telegram' }).click();
  await expect(account.getByLabel('Имя пользователя')).toHaveValue('MiniAppPlayer');
  await account.getByRole('button', { name: 'Завершить регистрацию' }).click();
  await expect(page.getByRole('button', { name: 'Аккаунт: MiniAppPlayer' })).toBeVisible();
  expect(
    await page.evaluate(() => document.querySelector('script[src*="telegram-login.js"]')),
  ).toBeNull();
});
