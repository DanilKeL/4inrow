import { expect, test } from '@playwright/test';
import { columnPosition, openGame } from './helpers';

for (const mobile of [false, true]) {
  test(`daily retry restores opaque preset pieces after a real bot win (${mobile ? 'mobile' : 'desktop'})`, async ({
    page,
  }) => {
    if (mobile) await page.setViewportSize({ width: 390, height: 844 });
    await openGame(page);
    await page.evaluate(async () => {
      const storePath = '/src/store/gameStore.ts';
      const dailyPath = '/src/game/daily.ts';
      const { useGame } = await import(storePath);
      const { dailyDate, dailyExpiresAt } = await import(dailyPath);
      const date = dailyDate();
      // Legal layered preset: a missed block lets the real deterministic worker win.
      useGame.getState().startDaily({
        id: `daily-1-${date}`,
        date,
        version: 1,
        expiresAt: dailyExpiresAt(date),
        preset: [
          { x: 0, y: 4 },
          { x: 0, y: 0 },
          { x: 1, y: 4 },
          { x: 1, y: 0 },
          { x: 2, y: 4 },
          { x: 2, y: 0 },
          { x: 2, y: 2 },
          { x: 2, y: 2 },
          { x: 2, y: 2 },
          { x: 2, y: 2 },
          { x: 4, y: 3 },
          { x: 4, y: 2 },
        ],
      });
    });
    await expect(page.getByTestId('move-count')).toHaveText('0');
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.getByRole('button', { name: 'Сверху', exact: true }).click();
    await page.getByRole('button', { name: 'Закрыть меню вида', exact: true }).click();
    await page.waitForTimeout(1100);
    for (let attempt = 0; attempt < 2; attempt++) {
      const point = await columnPosition(page, 4, 4);
      await page.mouse.click(point.screenX, point.screenY);
      await expect(page.getByRole('heading', { name: 'Поражение', exact: true })).toBeVisible();
      const before = await page.evaluate(() => window.__fourScene!.getRenderedPieces());
      expect(before.some((piece) => piece.opacities.every((opacity) => opacity === 0.52))).toBe(
        true,
      );
      await page.getByRole('button', { name: 'Повторить задачу', exact: true }).click();
      await expect(page.getByTestId('move-count')).toHaveText('0');
      await expect
        .poll(async () => {
          const pieces = await page.evaluate(() => window.__fourScene!.getRenderedPieces());
          return (
            pieces.length === 12 &&
            pieces.every(
              (piece) =>
                piece.opacities.length === 2 &&
                piece.opacities.every((opacity) => opacity === 1) &&
                piece.transparent.every((value) => !value) &&
                piece.depthWrite.every(Boolean),
            )
          );
        })
        .toBe(true);
      // Restart changes the camera back to perspective; use real controls for the next move.
      await page.getByRole('button', { name: 'Вид', exact: true }).click();
      await page.getByRole('button', { name: 'Сверху', exact: true }).click();
      await page.getByRole('button', { name: 'Закрыть меню вида', exact: true }).click();
      await page.waitForTimeout(1100);
    }
    // The fix must preserve deliberately enabled X-ray and its normal off transition.
    await page.getByRole('button', { name: 'Рентген', exact: true }).click();
    await expect
      .poll(() =>
        page.evaluate(() =>
          window
            .__fourScene!.getRenderedPieces()
            .every((piece) => piece.opacities.every((opacity) => opacity === 0.43)),
        ),
      )
      .toBe(true);
    await page.getByRole('button', { name: 'Рентген', exact: true }).click();
    await expect
      .poll(() =>
        page.evaluate(() =>
          window
            .__fourScene!.getRenderedPieces()
            .every((piece) => piece.opacities.every((opacity) => opacity === 1)),
        ),
      )
      .toBe(true);
  });
}
