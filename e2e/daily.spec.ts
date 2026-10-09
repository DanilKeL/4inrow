import { expect, test, type Page } from '@playwright/test';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { columnPosition } from './helpers';
import { replay } from '../src/game/core';
import type { GeneratedDailyChallenge } from '../server/dailyGenerator';
import type { DailyResponse } from '../src/game/daily';

const fixtures = new Map<string, Promise<GeneratedDailyChallenge>>();
function dailyFixture(date: string): Promise<GeneratedDailyChallenge> {
  const existing = fixtures.get(date);
  if (existing) return existing;
  // Run with the same tsx loader as the API worker; Playwright's own loader cannot import
  // the generator's existing JSON level fallback without rewriting production sources.
  const fixture = promisify(execFile)(
    process.execPath,
    [
      '--import',
      'tsx',
      '--input-type=module',
      '--eval',
      "import {generateDailyChallenge} from './server/dailyGenerator.ts'; process.stdout.write(JSON.stringify(generateDailyChallenge(process.argv[1])));",
      date,
    ],
    { windowsHide: true, timeout: 60000 },
  ).then(({ stdout }) => JSON.parse(stdout) as GeneratedDailyChallenge);
  fixtures.set(date, fixture);
  return fixture;
}

async function openDaily(page: Page) {
  await page.goto('/');
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await page.getByRole('button', { name: 'Задача дня', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Задача дня', exact: true });
  await expect(dialog.getByRole('button', { name: 'Играть', exact: true })).toBeEnabled();
  return dialog;
}

async function topView(page: Page) {
  await page.waitForFunction(() => Boolean(window.__fourScene));
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.getByRole('button', { name: 'Сверху', exact: true }).click();
  await page.getByRole('button', { name: 'Закрыть меню вида', exact: true }).click();
  await page.waitForTimeout(1100);
}

async function dailyMove(page: Page, move: { x: number; y: number }, count: number) {
  await expect(page.getByTestId('turn-status')).toContainText('Ваш ход');
  const point = await columnPosition(page, move.x, move.y);
  await page.mouse.click(point.screenX, point.screenY);
  await expect(page.getByTestId('move-count')).toHaveText(String(count));
}

async function dailyData(page: Page): Promise<DailyResponse> {
  const response = await page.request.get('/daily');
  expect(response.ok()).toBe(true);
  const data: DailyResponse = await response.json();
  const position = replay(data.challenge.preset);
  expect(position.status).toBe('playing');
  expect(Math.max(...position.heights)).toBeGreaterThanOrEqual(3);
  expect(position.history.some((move) => move.z >= 2)).toBe(true);
  expect(data.challenge).not.toHaveProperty('solution');
  return data;
}

test('daily win is checked by the server, survives resume and appears in the day table', async ({
  page,
}, info) => {
  test.setTimeout(120000);
  const username = `Daily_${Date.now().toString(36)}`;
  const registration = await page.request.post('/auth/register', {
    headers: { 'x-real-ip': '127.0.2.50' },
    data: { username, email: `${username}@example.test`, password: 'daily-browser-pass-123' },
  });
  expect(registration.ok()).toBe(true);
  const data = await dailyData(page);
  expect(data.ownBest).toBeNull();
  const generated = await dailyFixture(data.challenge.date);
  expect(generated.challenge).toEqual(data.challenge);
  expect(generated.solution.length).toBeGreaterThanOrEqual(2);

  const dialog = await openDaily(page);
  await dialog.getByRole('button', { name: 'Играть', exact: true }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0');
  await expect(page.getByRole('button', { name: 'Отменить ход', exact: true })).toHaveCount(0);
  await topView(page);
  await dailyMove(page, generated.solution[0], 1);
  await expect(page.getByTestId('turn-status')).toContainText('Ваш ход');

  // A real browser reload restores the exact day's board and completed bot response.
  await page.reload();
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  const resume = page.getByRole('dialog', { name: 'Продолжить партию?', exact: true });
  await expect(resume).toBeVisible();
  await resume.getByRole('button', { name: 'Продолжить', exact: true }).click();
  await expect(page.getByTestId('move-count')).toHaveText('1');
  await expect(page.getByTestId('turn-status')).toContainText('Ваш ход');
  await topView(page);

  const submitted = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === '/daily/results' &&
      response.request().method() === 'POST',
  );
  for (let index = 1; index < generated.solution.length; index++)
    await dailyMove(page, generated.solution[index], index + 1);
  const response = await submitted;
  expect(response.ok()).toBe(true);
  expect(response.request().postDataJSON()).toEqual({
    challengeId: data.challenge.id,
    owner: username,
    moves: generated.solution,
  });
  await expect(page.getByRole('heading', { name: 'Задача решена', exact: true })).toBeVisible();
  await expect(page.getByTestId('daily-result')).toContainText('Результат подтверждён');
  await expect(
    page.getByText('ЛИЧНЫЙ РЕКОРД', { exact: true }).locator('..').locator('strong'),
  ).toHaveText(String(generated.solution.length));
  await page.screenshot({ path: info.outputPath('daily-verified-win.png') });
  await page.getByRole('button', { name: 'Результаты дня', exact: true }).click();
  await expect(dialog.getByRole('table')).toBeVisible();
  const row = dialog.getByRole('row').filter({ hasText: username });
  await expect(row).toContainText(String(generated.solution.length));

  // Duplicate accepted attempts improve neither the score nor the number of table entries.
  const repeated = await page.request.post('/daily/results', {
    data: { challengeId: data.challenge.id, owner: username, moves: generated.solution },
  });
  expect(repeated.ok()).toBe(true);
  const saved = await dailyData(page);
  expect(saved.ownBest).toBe(generated.solution.length);
  expect(saved.leaderboard.filter((entry) => entry.username === username)).toHaveLength(1);
  const entry = saved.leaderboard.find((candidate) => candidate.username === username)!;
  expect(entry.moves).toBe(generated.solution.length);
  expect(entry.rank).toBeGreaterThan(0);

  await page.reload();
  await openDaily(page);
  await dialog.getByRole('button', { name: 'Результаты', exact: true }).click();
  await expect(dialog.getByRole('row').filter({ hasText: username })).toBeVisible();
  await page.screenshot({ path: info.outputPath('daily-day-results.png') });
});

test('guest plays the same layered daily position on mobile without submitting a score', async ({
  page,
}, info) => {
  test.setTimeout(120000);
  await page.setViewportSize({ width: 390, height: 844 });
  const data = await dailyData(page);
  const generated = await dailyFixture(data.challenge.date);
  let submitted = 0;
  page.on('request', (request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === '/daily/results')
      submitted++;
  });
  const dialog = await openDaily(page);
  expect(
    await dialog.evaluate((element) => {
      const bounds = element.getBoundingClientRect();
      return (
        bounds.top >= 0 &&
        bounds.bottom <= innerHeight + 1 &&
        element.scrollHeight <= element.clientHeight + 1
      );
    }),
  ).toBe(true);
  await page.screenshot({ path: info.outputPath('daily-mobile.png') });
  await dialog.getByRole('button', { name: 'Играть', exact: true }).click();
  await topView(page);
  for (const [index, move] of generated.solution.entries()) await dailyMove(page, move, index + 1);
  await expect(page.getByRole('heading', { name: 'Задача решена', exact: true })).toBeVisible();
  await expect(page.getByTestId('daily-result')).toContainText('нужен аккаунт');
  expect(submitted).toBe(0);
  expect((await dailyData(page)).ownBest).toBeNull();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: info.outputPath('daily-mobile-guest-win.png') });
  await page.getByRole('button', { name: 'Результаты дня', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Результаты', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
});
