import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
import { createOnlineServer } from '../server/app.ts';
import { createAdminPasswordHash } from '../server/admin.ts';
import { StatisticsStore } from '../server/statistics.ts';
import { createGame, makeMove, serialize } from '../src/game/core/index.ts';

const directory = await mkdtemp(join(tmpdir(), 'four-analytics-'));
const statsFile = join(directory, 'statistics.sqlite');
const password = 'analytics-browser-test-123';
let app;
let browser;
const errors = [];
const names = ['Alex', 'Victoria', 'Danil', 'Max', 'Sofia'];
function position(loss = false) {
  let game = createGame();
  const moves = loss
    ? [
        [4, 4],
        [0, 0],
        [4, 3],
        [1, 0],
        [4, 2],
        [2, 0],
        [3, 3],
        [3, 0],
      ]
    : [
        [0, 0],
        [4, 4],
        [1, 0],
        [4, 3],
        [2, 0],
        [4, 2],
        [3, 0],
      ];
  for (const [x, y] of moves) game = makeMove(game, x, y).state;
  assert.equal(game.status, 'won');
  return game;
}
try {
  const seed = new StatisticsStore(statsFile);
  for (let day = 0; day < 7; day++) {
    const stamp = Date.now() - (6 - day) * 86400000 - 3600000;
    for (let i = 0; i < 12 + day * 4; i++) {
      const base = {
        session: `session-${day}-${String(i).padStart(5, '0')}`,
        visitor: `visitor-${String(i).padStart(5, '0')}`,
        occurredAt: stamp,
      };
      const owner = i % 4 === 0 ? null : names[i % names.length];
      const identity = owner ?? `Гость_${100000 + i}`;
      seed.analytics.ingest(
        {
          ...base,
          type: 'visit',
          device: i % 3 === 0 ? 'desktop' : 'mobile',
          browser: i % 2 ? 'Safari' : 'Chrome',
          referrer: i % 5 === 0 ? 'https://yandex.ru/search' : '',
        },
        owner,
        identity,
      );
      seed.analytics.ingest(
        { ...base, type: 'heartbeat', activeSeconds: 120 + i * 3 },
        owner,
        identity,
      );
      if (i % 4 === 0) continue;
      const mode = i % 5 === 0 ? 'local' : 'ai';
      const id = `local-fixture-${day}-${String(i).padStart(5, '0')}`;
      seed.analytics.ingest(
        { ...base, type: 'game_start', id, mode, difficulty: ['easy', 'medium', 'hard'][i % 3] },
        owner,
        identity,
      );
      if (i % 7 === 0)
        seed.analytics.ingest({ ...base, type: 'game_abandon', id, elapsed: 40 }, owner);
      else
        seed.analytics.ingest(
          {
            ...base,
            type: 'game_end',
            id,
            game: serialize(position(i % 3 === 2)),
            elapsed: 60 + i * 12,
          },
          owner,
        );
      if (i % 6 === 0) {
        seed.analytics.onlineStart(
          `online-fixture-${day}-${i}`,
          'ranked',
          [owner, names[(i + 1) % names.length]],
          stamp,
        );
        seed.analytics.onlineEnd(
          `online-fixture-${day}-${i}`,
          position(),
          90 + i * 5,
          stamp + 100000,
        );
      }
    }
  }
  seed.close();
  app = createOnlineServer({
    staticDir: resolve('dist'),
    authFile: null,
    statsFile,
    adminPasswordHash: await createAdminPasswordHash(password),
    mailer: null,
  });
  await new Promise((done) => app.httpServer.listen(0, '127.0.0.1', done));
  const url = `http://127.0.0.1:${app.httpServer.address().port}`;
  for (const username of names) {
    const response = await fetch(`${url}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password: 'player-browser-test-123' }),
    });
    assert.equal(response.status, 200);
  }
  const edge = join(
    process.env['PROGRAMFILES(X86)'] ?? '',
    'Microsoft',
    'Edge',
    'Application',
    'msedge.exe',
  );
  const channel =
    process.env.PLAYWRIGHT_CHANNEL ??
    (!existsSync(chromium.executablePath()) && existsSync(edge) ? 'msedge' : undefined);
  browser = await chromium.launch({ channel });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`${url}/admin`);
  await page.getByLabel('Логин', { exact: true }).fill('admin');
  await page.getByLabel('Пароль', { exact: true }).fill(password);
  await page.getByRole('button', { name: 'Войти', exact: true }).click();
  await page.getByRole('heading', { name: 'Статистика', exact: true }).waitFor();
  await page.getByRole('button', { name: '7 дней', exact: true }).click();
  await page.waitForFunction(
    () =>
      document.querySelector('[aria-label="Статистика игры"]')?.getAttribute('aria-busy') ===
      'false',
  );
  const analytics = await (await page.request.get(`${url}/admin-api/analytics`)).json();
  assert(analytics.summary.visitors > 10 && analytics.summary.completed > 30);
  assert(analytics.bots.length === 3);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  await mkdir(resolve('artifacts'), { recursive: true });
  await page.screenshot({ path: 'artifacts/analytics-desktop.png' });
  await page.getByRole('button', { name: 'Боты', exact: true }).click();
  await page.getByRole('heading', { name: 'Игра против ботов', exact: true }).waitFor();
  await page.screenshot({ path: 'artifacts/analytics-bots.png' });
  await page
    .getByRole('navigation', { name: 'Разделы статистики' })
    .getByRole('button', { name: 'Игроки', exact: true })
    .click();
  await page.getByRole('heading', { name: 'Активность игроков', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Alex', exact: true }).click();
  await page.getByRole('heading', { name: 'Alex', exact: true }).waitFor();
  const csv = page.waitForEvent('download');
  await page.getByRole('button', { name: 'CSV', exact: true }).click();
  assert.match((await csv).suggestedFilename(), /four-players.*\.csv$/);
  await page.getByRole('button', { name: 'Уровни', exact: true }).click();
  assert.equal(await page.locator('tbody tr').count(), 40);
  await page.getByRole('button', { name: 'Обзор', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  await page.screenshot({ path: 'artifacts/analytics-mobile.png' });
  await page.getByRole('button', { name: 'Боты', exact: true }).click();
  await page.screenshot({ path: 'artifacts/analytics-mobile-bots.png' });

  // Real production UI: a local game and a level must be tracked separately.
  const player = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  player.on('pageerror', (e) => errors.push(e.message));
  await player.goto(url);
  await player.getByRole('button', { name: 'Вдвоём', exact: true }).click();
  await player.getByRole('button', { name: 'Начать игру', exact: true }).click();
  await player.getByRole('button', { name: /Начать/ }).click();
  await player.waitForTimeout(1200);
  const afterLocal = await (await page.request.get(`${url}/admin-api/analytics`)).json();
  assert.equal(afterLocal.summary.started, analytics.summary.started + 1);
  await player.reload();
  await player.getByRole('button', { name: 'Уровни', exact: true }).click();
  await player.getByRole('button', { name: 'Уровень 1', exact: true }).click();
  await player.waitForTimeout(1200);
  const afterLevel = await (await page.request.get(`${url}/admin-api/analytics`)).json();
  assert.equal(afterLevel.modes.find((m) => m.mode === 'level').started, 1);
  assert.equal(
    afterLevel.modes.find((m) => m.mode === 'ai').started,
    analytics.modes.find((m) => m.mode === 'ai').started,
  );
  assert.equal(afterLevel.levels[0].level, 1);
  assert.deepEqual(errors, []);
  console.log(
    'Analytics browser verification passed: authenticated dashboard, real SQLite aggregates, four sections, player details, CSV export, desktop/mobile layout, actual local/level telemetry and no phantom AI start.',
  );
} finally {
  await browser?.close();
  await app?.close();
  await rm(directory, { recursive: true, force: true });
}
