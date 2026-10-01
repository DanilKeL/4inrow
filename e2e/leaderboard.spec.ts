import { expect, test } from '@playwright/test';

for (const viewport of [
  { width: 1366, height: 768 },
  { width: 390, height: 844 },
  { width: 844, height: 390 },
]) {
  test(`public leaderboard fits ${viewport.width}x${viewport.height} and scrolls all 100 players`, async ({
    page,
  }) => {
    await page.setViewportSize(viewport);
    await page.route('**/auth/leaderboard', (route) =>
      route.fulfill({
        json: {
          players: Array.from({ length: 100 }, (_, index) => ({
            rank: index + 1,
            username: `Player_${index + 1}`,
            elo: 1800 - index,
            games: 120 - index,
          })),
        },
      }),
    );
    await page.goto('/');
    await expect(page.getByTestId('loading-screen')).toBeHidden();
    const button = page.getByRole('button', { name: 'Рейтинг игроков', exact: true });
    await expect(button).toBeVisible();
    const bounds = await button.boundingBox();
    expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(viewport.height);
    await button.click();
    const dialog = page.getByRole('dialog', { name: 'Рейтинг игроков' });
    await expect(dialog.getByRole('row')).toHaveCount(101);
    await expect(dialog.getByRole('row').nth(1)).toContainText('Player_1');
    const last = dialog.getByRole('row').last();
    await last.scrollIntoViewIfNeeded();
    await expect(last).toContainText('Player_100');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    await dialog.getByRole('button', { name: 'Закрыть', exact: true }).click();
    await expect(dialog).toBeHidden();
  });
}

test('guest can recover from a failed leaderboard request', async ({ page }) => {
  let fail = true;
  await page.route('**/auth/leaderboard', (route) =>
    route.fulfill(
      fail
        ? { status: 503, json: {} }
        : { json: { players: [{ rank: 1, username: 'Champion', elo: 1400, games: 25 }] } },
    ),
  );
  await page.goto('/');
  await expect(page.getByTestId('loading-screen')).toBeHidden();
  await page.getByRole('button', { name: 'Рейтинг игроков', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Рейтинг игроков' });
  await expect(dialog.getByRole('alert')).toContainText('Не удалось');
  fail = false;
  await dialog.getByRole('button', { name: 'Попробовать снова' }).click();
  await expect(dialog.getByRole('table')).toContainText('Champion');
});
