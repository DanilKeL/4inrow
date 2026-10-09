import { chromium, expect, test, type Page } from '@playwright/test';
import { PerspectiveCamera, Vector3 } from 'three';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { strict as assert } from 'node:assert';

async function ready(page: Page) {
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await page.waitForFunction(() => Boolean(navigator.serviceWorker.controller));
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          new Promise<boolean>((resolve) => {
            const channel = new MessageChannel();
            const timer = setTimeout(() => {
              channel.port1.close();
              resolve(false);
            }, 2000);
            channel.port1.onmessage = (event) => {
              clearTimeout(timer);
              channel.port1.close();
              resolve(Boolean(event.data?.ready));
            };
            navigator.serviceWorker.controller!.postMessage({ type: 'offline-status' }, [
              channel.port2,
            ]);
          }),
      ),
    )
    .toBe(true);
}
async function topView(page: Page) {
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.getByRole('button', { name: 'Сверху', exact: true }).click();
  await page.getByRole('button', { name: 'Закрыть меню вида', exact: true }).click();
  await page.waitForTimeout(1000);
}
async function column(page: Page, x: number, y: number, height = 0) {
  const bounds = (await page.locator('canvas').boundingBox())!;
  const camera = new PerspectiveCamera(35, bounds.width / bounds.height, 0.1, 100);
  camera.position.set(0, 13.7, 0.035).multiplyScalar(Math.max(1, 0.9 / camera.aspect));
  camera.lookAt(0, 0.25, 0);
  camera.updateMatrixWorld();
  const point = new Vector3((x - 2) * 1.09, 0.13 + height * 0.5, (y - 2) * 1.09).project(camera);
  await page.mouse.click(
    bounds.x + ((point.x + 1) * bounds.width) / 2,
    bounds.y + ((1 - point.y) * bounds.height) / 2,
  );
}
for (const viewport of [
  { width: 1440, height: 900 },
  { width: 320, height: 568 },
]) {
  test(`cold offline restart restores AI and all video rules at ${viewport.width}px`, async ({
    baseURL,
  }, info) => {
    // Chromium CacheStorage can fail on Windows when a profile path is too long.
    const profile = await mkdtemp(join(tmpdir(), 'four-offline-'));
    const channel = info.project.use.channel as string | undefined;
    let context = await chromium.launchPersistentContext(profile, { channel, viewport });
    await context.addInitScript(() =>
      navigator.serviceWorker.addEventListener('message', (event) => {
        if (event.data?.type === 'offline-error')
          console.error('Offline preparation:', event.data.reason);
      }),
    );
    context.on('console', (message) => {
      if (message.type() === 'error') console.log('Offline browser:', message.text());
    });
    try {
      let page = await context.newPage();
      await page.goto(baseURL!);
      await ready(page);
      await page.getByRole('button', { name: 'Против AI', exact: true }).click();
      await page.getByRole('button', { name: 'Начать игру', exact: true }).click();
      await page.getByRole('button', { name: 'Начать', exact: true }).click();
      const canvas = (await page.locator('canvas').boundingBox())!;
      await page.mouse.click(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2);
      await expect(page.getByTestId('move-count')).toHaveText('2 / 125');
      await context.close();
      context = await chromium.launchPersistentContext(profile, {
        channel,
        viewport,
        offline: true,
      });
      page = await context.newPage();
      const navigation = await page.goto(baseURL!);
      expect(navigation?.fromServiceWorker()).toBe(true);
      await expect(page.getByTestId('loading-screen')).toBeHidden();
      await expect(page.getByText('Доступно без интернета', { exact: true })).toHaveCount(0);
      expect(
        await page.evaluate(() => document.documentElement.scrollHeight - innerHeight),
      ).toBeLessThanOrEqual(1);
      await expect(page.getByRole('button', { name: 'Онлайн', exact: true })).toBeDisabled();
      await page
        .getByRole('dialog', { name: 'Продолжить партию?' })
        .getByRole('button', { name: 'Продолжить', exact: true })
        .click();
      await expect(page.getByTestId('move-count')).toHaveText('2 / 125');
      await page.mouse.click(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2);
      await expect(page.getByTestId('move-count')).toHaveText('4 / 125');
      await page.getByRole('button', { name: 'Как играть', exact: true }).click();
      const examples = page.getByRole('navigation', { name: 'Примеры правил' }).getByRole('button');
      expect(await examples.count()).toBe(6);
      for (let i = 0; i < 6; i++) {
        await examples.nth(i).click();
        await expect
          .poll(() =>
            page.locator('video').evaluate((video: HTMLVideoElement) => video.currentTime),
          )
          .toBeGreaterThan(0);
      }
      const range = await page.evaluate(async () => {
        const response = await fetch('/tutorial/horizontal.mp4', {
          headers: { Range: 'bytes=100-199' },
        });
        return { status: response.status, bytes: (await response.arrayBuffer()).byteLength };
      });
      expect(range).toEqual({ status: 206, bytes: 100 });
      expect(
        await page.evaluate(() =>
          fetch('/auth/me')
            .then(() => true)
            .catch(() => false),
        ),
      ).toBe(false);
      const cached = await page.evaluate(async () =>
        (
          await Promise.all(
            (await caches.keys()).map(async (key) =>
              (await (await caches.open(key)).keys()).map(
                (request) => new URL(request.url).pathname,
              ),
            ),
          )
        ).flat(),
      );
      expect(cached.some((path) => /^\/(auth|admin|health|telemetry)/.test(path))).toBe(false);
      await page.getByRole('button', { name: 'Понятно', exact: true }).click();
      await context.setOffline(false);
      await page.screenshot({ path: info.outputPath('offline-game.png') });
    } finally {
      await context.close();
      assert(
        dirname(resolve(profile)) === resolve(tmpdir()) &&
          basename(profile).startsWith('four-offline-'),
        'Unexpected test profile path',
      );
      await rm(profile, { recursive: true, force: true, maxRetries: 3, retryDelay: 300 });
    }
  });
}

test('declining the resume banner clears its save and keeps the ranked menu button', async ({
  page,
}) => {
  await page.goto('/');
  await ready(page);
  await page.getByRole('button', { name: 'Вдвоём', exact: true }).click();
  await page.getByRole('button', { name: 'Начать игру', exact: true }).click();
  await page.getByRole('button', { name: 'Начать', exact: true }).click();
  const board = (await page.locator('canvas').boundingBox())!;
  await page.mouse.click(board.x + board.width / 2, board.y + board.height / 2);
  await expect(page.getByTestId('move-count')).toHaveText('1 / 125');
  await page.reload();
  const banner = page.getByRole('dialog', { name: 'Продолжить партию?' });
  await expect(banner).toBeVisible();
  const menu = page.getByRole('region', { name: 'Режимы игры' });
  await expect(menu.getByRole('button', { name: 'Рейтинговая игра', exact: true })).toBeVisible();
  await expect(menu.getByRole('button', { name: /Продолжить/ })).toHaveCount(0);
  await banner.getByRole('button', { name: 'Не продолжать', exact: true }).click();
  await expect(banner).toBeHidden();
  expect(await page.evaluate(() => localStorage.getItem('four-cubed-active-game-v1'))).toBeNull();
  await page.reload();
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await expect(banner).toBeHidden();
  await page.getByRole('button', { name: 'Против AI', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Новая игра' })).toBeVisible();
});

test('offline account level win survives reload and syncs to its account', async ({
  page,
  context,
}) => {
  const username = `Offline${Date.now()}`;
  const registration = await context.request.post('/auth/register', {
    data: { username, email: `${username}@example.com`, password: 'offline-password-123' },
  });
  expect(registration.ok()).toBe(true);
  await page.goto('/');
  await ready(page);
  await expect(
    page.getByRole('button', { name: `Аккаунт: ${username}`, exact: true }),
  ).toBeVisible();
  await context.setOffline(true);
  await page.reload();
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await expect(
    page.getByRole('button', { name: `Аккаунт: ${username}`, exact: true }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Уровни', exact: true }).click();
  await page.getByRole('button', { name: 'Уровень 1', exact: true }).click();
  await topView(page);
  await column(page, 1, 0);
  await expect(page.getByTestId('turn-status')).toContainText('Партия завершена');
  await page.reload();
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await page.getByRole('button', { name: 'Уровни', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Уровень 1', exact: true })).toContainText(
    'Рекорд: 1 ход',
  );
  await context.setOffline(false);
  await expect
    .poll(async () => (await (await context.request.get('/auth/levels')).json()).best?.['1'])
    .toBe(1);
});

test('a failed update retains offline play; a complete update activates after closing the game', async ({
  page,
  context,
}) => {
  const path = 'dist/match-notifications.js';
  const original = await readFile(path, 'utf8');
  const match = /const OFFLINE_BUILD = (.*);/.exec(original)!;
  const build = JSON.parse(match[1]);
  const changed = (value: unknown) =>
    original.replace(match[0], `const OFFLINE_BUILD = ${JSON.stringify(value)};`);
  await page.goto('/');
  await ready(page);
  try {
    await writeFile(
      path,
      changed({
        ...build,
        version: `${build.version}-broken`,
        entries: [{ ...build.entries[0], url: '/missing-offline-file.glb' }],
      }),
    );
    await page.evaluate(async () => {
      await (await navigator.serviceWorker.getRegistration())!.update();
    });
    await expect
      .poll(() =>
        page.evaluate(async () => {
          const registration = (await navigator.serviceWorker.getRegistration())!;
          return !registration.installing && !registration.waiting;
        }),
      )
      .toBe(true);
    expect(await page.evaluate(() => caches.keys())).not.toContain(
      `four-offline-${build.version}-broken`,
    );
    await context.setOffline(true);
    expect((await page.reload())?.fromServiceWorker()).toBe(true);
    await expect(page.getByTestId('loading-screen')).toBeHidden();
    await context.setOffline(false);
    await writeFile(path, changed({ ...build, version: `${build.version}-next` }));
    await page.evaluate(async () => {
      await (await navigator.serviceWorker.getRegistration())!.update();
    });
    await expect
      .poll(() =>
        page.evaluate(async () =>
          Boolean((await navigator.serviceWorker.getRegistration())?.waiting),
        ),
      )
      .toBe(true);
    const status = await page.evaluate(
      async () =>
        new Promise<{ version: string }>((resolve) => {
          const channel = new MessageChannel();
          channel.port1.onmessage = (event) => {
            channel.port1.close();
            resolve(event.data);
          };
          navigator.serviceWorker.controller!.postMessage({ type: 'offline-status' }, [
            channel.port2,
          ]);
        }),
    );
    expect(status.version).toBe(build.version);
    await page.reload();
    await expect(page.getByTestId('loading-screen')).toBeHidden();
    await expect(page.getByRole('button', { name: 'Обновить игру', exact: true })).toHaveCount(0);
    const workers = context.serviceWorkers();
    const versions = await Promise.all(
      workers.map((worker) => worker.evaluate('OFFLINE_BUILD.version').catch(() => null)),
    );
    const nextWorker = workers[versions.indexOf(`${build.version}-next`)];
    expect(nextWorker).toBeDefined();
    await page.close();
    await expect
      .poll(() =>
        nextWorker.evaluate(
          "self.registration.active?.state === 'activated' && !self.registration.waiting",
        ),
      )
      .toBe(true);
    const reopened = await context.newPage();
    await reopened.goto('/');
    await ready(reopened);
    const version = await reopened.evaluate(
      () =>
        new Promise<string>((resolve) => {
          const channel = new MessageChannel();
          channel.port1.onmessage = (event) => {
            channel.port1.close();
            resolve(event.data.version);
          };
          navigator.serviceWorker.controller!.postMessage({ type: 'offline-status' }, [
            channel.port2,
          ]);
        }),
    );
    expect(version).toBe(`${build.version}-next`);
    await expect(reopened.getByRole('button', { name: 'Обновить игру', exact: true })).toHaveCount(
      0,
    );
    await context.setOffline(true);
    expect((await reopened.reload())?.fromServiceWorker()).toBe(true);
    await expect(reopened.getByTestId('loading-screen')).toBeHidden();
  } finally {
    await writeFile(path, original);
  }
});

test('repairs an evicted cache before reporting offline readiness', async ({ page, context }) => {
  await page.goto('/');
  await ready(page);
  await page.evaluate(async () => {
    const name = (await caches.keys()).find((key) => key.startsWith('four-offline-'))!;
    await (await caches.open(name)).delete('/models/four-board.glb');
  });
  await page.reload();
  await ready(page);
  await context.setOffline(true);
  expect((await page.reload())?.fromServiceWorker()).toBe(true);
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await expect(page.locator('canvas')).toBeVisible();
});
