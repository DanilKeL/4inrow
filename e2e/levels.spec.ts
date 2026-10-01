import { test, expect, type Page } from '@playwright/test';
import { columnPosition } from './helpers';
import solutions from '../src/game/levels/solutions.json' with { type: 'json' };

async function fits(page: Page) {
  expect(
    await page.evaluate(
      () =>
        document.documentElement.scrollHeight <= innerHeight + 1 &&
        document.documentElement.scrollWidth <= innerWidth + 1,
    ),
  ).toBe(true);
  for (const dialog of await page.getByRole('dialog').all()) {
    expect(
      await dialog.evaluate((el) => {
        const r = el.getBoundingClientRect();
        return r.top >= 0 && r.bottom <= innerHeight + 1 && el.scrollHeight <= el.clientHeight + 1;
      }),
    ).toBe(true);
  }
}
async function openLevels(page: Page) {
  await page.goto('/');
  await expect(page.getByTestId('loading-screen')).not.toBeVisible();
  await page.getByRole('button', { name: 'Уровни', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Уровни' })).toBeVisible();
}
async function win(page: Page, id: number, touch = false) {
  await page.waitForFunction(() => Boolean(window.__fourScene));
  // Dense presets can occlude a column in perspective. Use the player's top-view control.
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.getByRole('button', { name: 'Сверху', exact: true }).click();
  await page.getByRole('button', { name: 'Закрыть меню вида' }).click();
  await page.waitForTimeout(1100);
  const moves = solutions.find((level) => level.id === id)!.solution;
  for (const [i, move] of moves.entries()) {
    await expect(page.getByTestId('turn-status')).toContainText('Ваш ход');
    const p = await columnPosition(page, move.x, move.y);
    if (touch) await page.touchscreen.tap(p.screenX, p.screenY);
    else await page.mouse.click(p.screenX, p.screenY);
    await expect(page.getByTestId('move-count')).toHaveText(String(i + 1));
  }
  await expect(page.getByRole('heading', { name: 'Уровень пройден' })).toBeVisible();
  await expect(page.getByTestId('level-result')).toBeVisible();
  await page.waitForTimeout(700);
}

test('levels play offline with deterministic replies, preserve records and restart the same preset', async ({
  page,
  context,
}, info) => {
  test.setTimeout(60000);
  await openLevels(page);
  await page.getByRole('button', { name: 'Следующие уровни' }).click();
  await page.getByRole('button', { name: 'Уровень 9', exact: true }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0');
  await expect(page.getByRole('button', { name: 'Отменить ход', exact: true })).toHaveCount(0);
  await context.setOffline(true);
  try {
    await win(page, 9);
    await expect(page.getByTestId('level-result')).toHaveText('Новый рекорд · 3 хода');
    await page.screenshot({ path: info.outputPath('level-win-desktop.png') });
    await page.getByRole('button', { name: 'Повторить уровень' }).click();
    await expect(page.getByTestId('move-count')).toHaveText('0');
    await win(page, 9);
    await expect(page.getByTestId('level-result')).toHaveText('Победа · 3 хода');
    await page.getByRole('button', { name: 'К уровням' }).click();
    await expect(page.getByRole('button', { name: 'Уровень 9', exact: true })).toContainText(
      'Рекорд: 3 хода',
    );
  } finally {
    await context.setOffline(false);
  }
  await openLevels(page);
  await page.getByRole('button', { name: 'Следующие уровни' }).click();
  await expect(page.getByRole('button', { name: 'Уровень 9', exact: true })).toContainText(
    'Рекорд: 3 хода',
  );
});

for (const [width, height] of [
  [320, 568],
  [568, 320],
]) {
  test(`level selection and result fit ${width}x${height}`, async ({ browser, baseURL }, info) => {
    const page = await browser.newPage({
      baseURL,
      viewport: { width, height },
      isMobile: true,
      hasTouch: true,
    });
    try {
      await openLevels(page);
      await fits(page);
      await page.screenshot({ path: info.outputPath('levels-mobile.png') });
      for (let i = 0; i < 4; i++)
        await page.getByRole('button', { name: 'Следующие уровни' }).click();
      await expect(page.getByRole('button', { name: 'Уровень 40', exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Следующие уровни' })).toBeDisabled();
      for (let i = 0; i < 4; i++)
        await page.getByRole('button', { name: 'Предыдущие уровни' }).click();
      await page.getByRole('button', { name: 'Уровень 1', exact: true }).click();
      await win(page, 1, true);
      await fits(page);
      await page.screenshot({ path: info.outputPath('level-win-mobile.png') });
      await page.getByRole('button', { name: 'Следующий уровень' }).click();
      await expect(page.getByTestId('turn-status')).toContainText('Уровень 2');
      await expect(page.getByTestId('move-count')).toHaveText('0');
    } finally {
      await page.close();
    }
  });
}
