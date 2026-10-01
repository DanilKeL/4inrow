import { expect, type Page } from '@playwright/test';

interface ScreenColumn {
  x: number;
  y: number;
  screenX: number;
  screenY: number;
}

export async function openGame(page: Page, mode: 'local' | 'ai' = 'local') {
  await page.goto('/');
  await page.getByRole('button', { name: 'Вдвоём', exact: true }).click();
  const setup = page.getByRole('dialog', { name: 'Новая игра' });
  await setup.waitFor();
  await setup.getByRole('button', { name: mode === 'local' ? /Вдвоём/ : /Против AI/ }).click();
  if (mode === 'ai') await page.getByRole('button', { name: 'Сложно', exact: true }).click();
  await page.getByRole('button', { name: 'Начать игру' }).click();
  const tutorial = page.getByRole('button', { name: /Начать/ });
  // First-launch tutorial is part of the real user flow, not bypassed in storage.
  await tutorial.click();
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  await page.waitForFunction(() =>
    Boolean(
      (
        window as unknown as {
          __fourScene?: { getColumnScreenPositions(): unknown[] };
        }
      ).__fourScene?.getColumnScreenPositions().length,
    ),
  );
  await page.waitForTimeout(500);
}

export async function openHistory(page: Page) {
  await page.getByRole('button', { name: /^Аккаунт:/ }).click();
  await page.getByRole('button', { name: 'История', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'История партий' })).toBeVisible();
}

export async function columnPosition(page: Page, x: number, y: number): Promise<ScreenColumn> {
  const columns = await page.evaluate(() =>
    (
      window as unknown as {
        __fourScene: { getColumnScreenPositions(): ScreenColumn[] };
      }
    ).__fourScene.getColumnScreenPositions(),
  );
  const column = columns.find((column) => column.x === x && column.y === y);
  if (!column) throw new Error(`No projected column ${x},${y}`);
  return column;
}

export async function place(
  page: Page,
  x: number,
  y: number,
  expectedMoves: number,
  touch = false,
) {
  const point = await columnPosition(page, x, y);
  if (touch) await page.touchscreen.tap(point.screenX, point.screenY);
  else await page.mouse.click(point.screenX, point.screenY);
  await expect(page.getByTestId('move-count')).toHaveText(`${expectedMoves} / 125`);
  await page.waitForTimeout(500);
}

export function collectErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') errors.push(message.text());
  });
  return errors;
}

export async function expectColumnsInsideCanvas(page: Page) {
  const geometry = await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    if (!canvas || !window.__fourScene) throw new Error('Canvas projection is not ready');
    const rect = canvas.getBoundingClientRect();
    return {
      bounds: { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom },
      columns: window.__fourScene.getColumnScreenPositions(),
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  });
  expect(geometry.columns).toHaveLength(25);
  expect(geometry.overflow).toBeLessThanOrEqual(0);
  for (const point of geometry.columns) {
    const label = `column (${point.x},${point.y}) at ${point.screenX},${point.screenY}`;
    expect(point.screenX, label).toBeGreaterThanOrEqual(geometry.bounds.left);
    expect(point.screenX, label).toBeLessThanOrEqual(geometry.bounds.right);
    expect(point.screenY, label).toBeGreaterThanOrEqual(geometry.bounds.top);
    expect(point.screenY, label).toBeLessThanOrEqual(geometry.bounds.bottom);
  }
}

/** Compare real screenshot pixels, ignoring small antialiasing changes. */
export async function screenshotDifference(page: Page, before: Buffer, after: Buffer) {
  return page.evaluate(
    async ([first, second]) => {
      const read = async (encoded: string) => {
        const image = new Image();
        image.src = `data:image/png;base64,${encoded}`;
        await image.decode();
        const canvas = document.createElement('canvas');
        canvas.width = image.width;
        canvas.height = image.height;
        const context = canvas.getContext('2d')!;
        context.drawImage(image, 0, 0);
        return context.getImageData(0, 0, image.width, image.height).data;
      };
      const a = await read(first),
        b = await read(second);
      if (a.length !== b.length) throw new Error('Screenshot dimensions changed');
      let changed = 0;
      for (let index = 0; index < a.length; index += 4) {
        if (
          Math.max(
            Math.abs(a[index] - b[index]),
            Math.abs(a[index + 1] - b[index + 1]),
            Math.abs(a[index + 2] - b[index + 2]),
          ) > 20
        )
          changed++;
      }
      return changed / (a.length / 4);
    },
    [before.toString('base64'), after.toString('base64')],
  );
}
