import { expect, test, type Locator, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import type { Skin } from '../src/skins/catalog';

let server: ChildProcess;
let url: string;

test.beforeAll(async () => {
  server = spawn(process.execPath, ['--import', 'tsx', 'e2e/skins-server.ts'], {
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  url = await new Promise<string>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error('Skin design test server did not start')),
      10000,
    );
    let output = '';
    server.stdout!.on('data', (data) => {
      output += String(data);
      const match = /http:\/\/127\.0\.0\.1:\d+/.exec(output);
      if (match) {
        clearTimeout(timer);
        resolve(match[0]);
      }
    });
    server.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    server.once('exit', (code) => {
      clearTimeout(timer);
      reject(new Error(`Skin design test server exited (${code})`));
    });
  });
});

test.afterAll(async () => {
  if (server?.exitCode === null)
    await new Promise<void>((resolve) => {
      server.once('exit', () => resolve());
      server.kill();
    });
});

async function openEditor(page: Page) {
  await page.goto(`${url}/admin`);
  await page.getByLabel('Пароль').fill('skin-browser-test-123');
  await page.getByRole('button', { name: 'Войти', exact: true }).click();
  await page.getByRole('button', { name: 'Оформление', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Новый стиль', exact: true })).toBeEnabled();
}

async function activeSkin(page: Page): Promise<Skin> {
  return page.evaluate(() => {
    const catalog = JSON.parse(localStorage.getItem('four-skins-v1')!);
    return catalog.skins.find((skin: { id: string }) => skin.id === catalog.activeSkinId);
  });
}

async function setSmallLayerSize(slider: Locator) {
  await slider.focus();
  await slider.press('Home');
  // Keyboard input also covers the accessible range control instead of mutating React state.
  for (let step = 0; step < 17; step++) await slider.press('ArrowRight');
  await expect(slider).toHaveValue('0.22');
}

async function emblemPng(page: Page): Promise<Buffer> {
  const data = await page.evaluate(() => {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 96;
    const context = canvas.getContext('2d')!;
    context.fillStyle = '#ff00df';
    context.fillRect(0, 0, 96, 96);
    context.fillStyle = '#00ffdf';
    context.beginPath();
    context.moveTo(48, 14);
    context.lineTo(82, 48);
    context.lineTo(48, 82);
    context.lineTo(14, 48);
    context.closePath();
    context.fill();
    return canvas.toDataURL('image/png').split(',')[1];
  });
  return Buffer.from(data, 'base64');
}

async function magentaPixels(page: Page): Promise<number> {
  const pixels = await page.getByTestId('game-canvas').screenshot();
  return page.evaluate(
    async (dataUrl) => {
      const image = new Image();
      image.src = dataUrl;
      await image.decode();
      const canvas = document.createElement('canvas');
      canvas.width = image.naturalWidth;
      canvas.height = image.naturalHeight;
      const context = canvas.getContext('2d')!;
      context.drawImage(image, 0, 0);
      const data = context.getImageData(0, 0, canvas.width, canvas.height).data;
      let total = 0;
      for (let i = 0; i < data.length; i += 4)
        if (
          data[i] > 70 &&
          data[i + 2] > 60 &&
          data[i] > data[i + 1] * 1.7 &&
          data[i + 2] > data[i + 1] * 1.5
        )
          total++;
      return total;
    },
    `data:image/png;base64,${pixels.toString('base64')}`,
  );
}

test('composed Nocturne skin uploads art, edits independent surfaces and survives live/offline play', async ({
  browser,
}, info) => {
  test.setTimeout(90000);
  const adminContext = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const playerContext = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const admin = await adminContext.newPage();
  const player = await playerContext.newPage();
  const errors: string[] = [];
  for (const page of [admin, player]) page.on('pageerror', (error) => errors.push(error.message));
  try {
    await player.goto(url);
    await expect(player.getByTestId('loading-screen')).not.toBeVisible();
    await player.getByRole('button', { name: 'Вдвоём', exact: true }).click();
    await player.getByRole('button', { name: 'Начать игру', exact: true }).click();
    await player.getByRole('button', { name: /Начать/ }).click();
    await player.waitForTimeout(1000);
    const board = (await player.locator('canvas').boundingBox())!;
    await player.mouse.click(board.x + board.width / 2, board.y + board.height / 2);
    await expect(player.getByTestId('move-count')).toHaveText('1 / 125');
    expect(await magentaPixels(player)).toBeLessThan(10);

    await openEditor(admin);
    await admin.getByRole('button', { name: /Ноктюрн/ }).click();
    await admin.getByRole('button', { name: 'Новый стиль', exact: true }).click();
    await admin.getByLabel('Название стиля').fill('Ноктюрн — композиция');
    await admin.getByTestId('skin-design-preset').click();
    const editor = admin.getByTestId('skin-design-editor');
    await editor.getByLabel('Узор поверхности').selectOption('artdeco');
    await editor.getByRole('slider', { name: 'Металличность', exact: true }).press('Home');
    await editor.getByRole('slider', { name: 'Матовая поверхность', exact: true }).press('End');
    await editor.getByLabel('Добавляемая фигура').selectOption('star');
    await editor.getByRole('button', { name: 'Добавить фигуру', exact: true }).click();
    await editor.getByLabel('Добавляемая фигура').selectOption('diamond');
    await editor.getByRole('button', { name: 'Добавить фигуру', exact: true }).click();
    await expect(editor.getByTestId('skin-layers').locator('li')).toHaveCount(3);
    await editor.getByRole('button', { name: 'Удалить слой 2', exact: true }).click();
    await expect(
      editor.getByRole('button', { name: 'Редактировать слой 2: Ромб', exact: true }),
    ).toBeVisible();

    const uploadResponse = admin.waitForResponse(
      (response) =>
        response.url().endsWith('/admin-api/skin-assets') && response.request().method() === 'POST',
    );
    await editor
      .getByTestId('skin-image-upload')
      .setInputFiles({ name: 'emblem.png', mimeType: 'image/png', buffer: await emblemPng(admin) });
    const uploaded = await uploadResponse;
    expect(uploaded.ok()).toBe(true);
    const { id: imageId } = (await uploaded.json()) as { id: string };
    expect(imageId).toMatch(/^[a-f0-9]{64}$/);
    await expect(
      editor.getByRole('button', { name: 'Редактировать слой 3: Изображение', exact: true }),
    ).toHaveAttribute('aria-pressed', 'true');
    await editor.getByLabel('Повторение слоя').selectOption('corners');
    await setSmallLayerSize(editor.getByRole('slider', { name: 'Размер слоя', exact: true }));
    await editor.getByRole('button', { name: 'Опустить слой 3', exact: true }).click();
    await expect(
      editor.getByRole('button', { name: 'Редактировать слой 2: Изображение', exact: true }),
    ).toBeVisible();
    await editor.getByRole('button', { name: 'Поднять слой 2', exact: true }).click();
    await expect(
      editor.getByRole('button', { name: 'Редактировать слой 3: Изображение', exact: true }),
    ).toBeVisible();

    await editor.getByTestId('skin-surface-darkCap').click();
    await expect(editor.getByLabel('Фигура слоя')).toHaveValue('moon');
    await editor.getByLabel('Фигура слоя').selectOption('lotus');
    await editor.getByLabel('Цвет декора').fill('#b5d9fa');
    await editor.getByTestId('skin-surface-lightCap').click();
    await expect(editor.getByLabel('Фигура слоя')).toHaveValue('sun');
    await editor.getByTestId('skin-surface-darkBody').click();
    await editor.getByLabel('Узор поверхности').selectOption('guilloche');
    await editor.getByTestId('skin-surface-lightBody').click();
    await expect(editor.getByLabel('Узор поверхности')).toHaveValue('botanical');
    await editor.getByTestId('skin-surface-board').click();
    await expect(editor.getByLabel('Узор поверхности')).toHaveValue('artdeco');
    expect((await activeSkin(player)).id).toBe('coffee-board');
    await admin.screenshot({ path: info.outputPath('skin-composition-editor.png') });
    await admin.getByRole('button', { name: 'Сохранить стиль', exact: true }).click();
    await expect(admin.getByRole('status')).toHaveText('Стиль сохранён.');
    await admin.getByRole('button', { name: 'Применить для всех', exact: true }).click();
    await expect.poll(async () => (await activeSkin(player)).name).toBe('Ноктюрн — композиция');
    const skin = await activeSkin(player);
    expect(skin.artwork).toBeUndefined();
    expect(skin.design!.surfaces.board.pattern).toBe('artdeco');
    expect(
      skin.design!.surfaces.board.layers.map((layer) =>
        layer.kind === 'motif' ? layer.motif : layer.imageId,
      ),
    ).toEqual(['laurel', 'diamond', imageId]);
    expect(skin.design!.surfaces.darkCap.layers[0]).toMatchObject({
      kind: 'motif',
      motif: 'lotus',
      color: '#b5d9fa',
    });
    expect(skin.design!.surfaces.lightCap.layers[0]).toMatchObject({ kind: 'motif', motif: 'sun' });
    expect(skin.design!.surfaces.darkBody.pattern).toBe('guilloche');
    expect(skin.design!.surfaces.lightBody.pattern).toBe('botanical');
    await expect(player.getByTestId('move-count')).toHaveText('1 / 125');
    await expect.poll(() => magentaPixels(player)).toBeGreaterThan(30);
    await player.screenshot({ path: info.outputPath('skin-composition-live.png') });
    await expect
      .poll(() =>
        player.evaluate(
          async (id) => Boolean(await caches.match(`/appearance/assets/${id}`)),
          imageId,
        ),
      )
      .toBe(true);
    await expect
      .poll(
        () => player.evaluate(async () => Boolean(await caches.match('/__four_offline_ready__'))),
        { timeout: 20000 },
      )
      .toBe(true);

    await playerContext.setOffline(true);
    await player.reload();
    await expect(player.getByTestId('loading-screen')).not.toBeVisible();
    await expect(player.getByRole('dialog', { name: 'Продолжить партию?' })).toBeVisible();
    await player.getByRole('button', { name: 'Продолжить', exact: true }).click();
    await expect(player.getByTestId('move-count')).toHaveText('1 / 125');
    expect((await activeSkin(player)).design).toEqual(skin.design);
    await expect.poll(() => magentaPixels(player)).toBeGreaterThan(30);
    await player.screenshot({ path: info.outputPath('skin-composition-offline.png') });
    expect(errors).toEqual([]);
  } finally {
    await playerContext.close();
    await adminContext.close();
  }
});

test('mobile composition editor keeps controls aligned and rejects vector uploads before sending them', async ({
  browser,
}, info) => {
  test.setTimeout(90000);
  const context = await browser.newContext({
    viewport: { width: 320, height: 740 },
    isMobile: true,
    hasTouch: true,
  });
  const admin = await context.newPage();
  const errors: string[] = [];
  let uploads = 0;
  admin.on('pageerror', (error) => errors.push(error.message));
  admin.on('request', (request) => {
    if (request.url().endsWith('/admin-api/skin-assets') && request.method() === 'POST') uploads++;
  });
  try {
    await openEditor(admin);
    await admin.getByRole('button', { name: /Классика/ }).click();
    await admin.getByRole('button', { name: 'Новый стиль', exact: true }).click();
    await admin.getByLabel('Название стиля').fill('Мобильная композиция');
    await admin.getByRole('button', { name: 'Создать композицию', exact: true }).click();
    const editor = admin.getByTestId('skin-design-editor');
    await editor.getByTestId('skin-surface-lightCap').click();
    await editor.getByLabel('Узор поверхности').selectOption('marble');
    await editor.getByLabel('Добавляемая фигура').selectOption('rings');
    await editor.getByRole('button', { name: 'Добавить фигуру', exact: true }).click();
    await editor.getByRole('button', { name: 'Дублировать слой', exact: true }).click();
    await expect(editor.getByTestId('skin-layers').locator('li')).toHaveCount(2);
    await editor.getByRole('button', { name: 'Удалить слой 2', exact: true }).click();
    await editor.getByTestId('skin-surface-darkBody').click();
    await expect(editor.getByLabel('Узор поверхности')).toHaveValue('none');
    await expect(editor.getByTestId('skin-layers')).toHaveCount(0);
    await editor.getByLabel('Узор поверхности').selectOption('botanical');
    await editor.getByLabel('Добавляемая фигура').selectOption('laurel');
    await editor.getByRole('button', { name: 'Добавить фигуру', exact: true }).click();
    await editor.getByLabel('Повторение слоя').selectOption('grid');
    await editor
      .getByTestId('skin-image-upload')
      .setInputFiles({
        name: 'unsafe.svg',
        mimeType: 'image/svg+xml',
        buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><circle r="20"/></svg>'),
      });
    await expect(editor.getByRole('alert')).toHaveText('Поддерживаются только PNG, JPEG и WebP.');
    expect(uploads).toBe(0);

    for (const width of [320, 390]) {
      await admin.setViewportSize({ width, height: 844 });
      await editor.getByTestId('skin-surface-tabs').scrollIntoViewIfNeeded();
      const tabs = editor.getByTestId('skin-surface-tabs');
      const dark = (await tabs.getByTestId('skin-surface-darkCap').boundingBox())!;
      const light = (await tabs.getByTestId('skin-surface-lightCap').boundingBox())!;
      expect(dark.x + dark.width).toBeLessThanOrEqual(light.x + 1);
      expect(Math.abs(dark.y - light.y)).toBeLessThan(1);
      expect(
        await admin.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1),
      ).toBe(true);
      expect(
        await editor.evaluate((element) => element.scrollWidth <= element.clientWidth + 1),
      ).toBe(true);
      await admin.screenshot({ path: info.outputPath(`skin-composition-mobile-${width}.png`) });
    }
    await editor.getByTestId('skin-surface-lightCap').click();
    await expect(editor.getByLabel('Узор поверхности')).toHaveValue('marble');
    await expect(editor.getByLabel('Фигура слоя')).toHaveValue('rings');
    await admin.getByRole('button', { name: 'Сохранить стиль', exact: true }).click();
    await expect(admin.getByRole('status')).toHaveText('Стиль сохранён.');
    expect(errors).toEqual([]);
  } finally {
    await context.close();
  }
});
