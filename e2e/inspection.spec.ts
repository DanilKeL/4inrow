import { expect, test, type Page } from '@playwright/test';
import { collectErrors, openGame, place, screenshotDifference } from './helpers';

async function prepare(page: Page, animations: boolean) {
  await openGame(page);
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('switch', { name: 'Анимации' }).setChecked(animations);
  await page.getByRole('switch', { name: 'Предпросмотр хода' }).uncheck();
  await page.getByRole('button', { name: 'Закрыть', exact: true }).click();
}

for (const animations of [false, true]) {
  test(`x-ray toggled on existing pieces matches pieces created transparent (animations ${animations})`, async ({
    page,
    context,
  }, testInfo) => {
    const errors = collectErrors(page);
    await prepare(page, animations);
    for (let count = 1; count <= 5; count++) await place(page, 2, 2, count);
    await page.mouse.move(10, 10);
    const opaque = await page.locator('canvas').screenshot();
    await page.getByRole('button', { name: 'Рентген', exact: true }).click();
    await page.mouse.move(10, 10);
    await page.waitForTimeout(500);
    const toggled = await page
      .locator('canvas')
      .screenshot({ path: testInfo.outputPath('toggled-xray.png') });

    const reference = await context.newPage();
    await reference.goto('/');
    // Reset first-launch preferences for the reference page's independent setup flow.
    await reference.evaluate(() => localStorage.removeItem('four-cubed-settings'));
    await prepare(reference, animations);
    await reference.getByRole('button', { name: 'Рентген', exact: true }).click();
    for (let count = 1; count <= 5; count++) await place(reference, 2, 2, count);
    await reference.mouse.move(10, 10);
    await reference.waitForTimeout(500);
    const initial = await reference
      .locator('canvas')
      .screenshot({ path: testInfo.outputPath('initial-xray.png') });
    expect(await screenshotDifference(page, toggled, initial)).toBeLessThan(0.002);
    await page.getByRole('button', { name: 'Рентген', exact: true }).click();
    await page.mouse.move(10, 10);
    await page.waitForTimeout(500);
    expect(
      await screenshotDifference(page, opaque, await page.locator('canvas').screenshot()),
    ).toBeLessThan(0.002);
    await expect(page.getByTestId('move-count')).toHaveText('5 / 125');
    expect(errors).toEqual([]);
    await reference.close();
  });
}

test('layers toggle independently and all layers restores the full tower', async ({
  page,
}, testInfo) => {
  const errors = collectErrors(page);
  await prepare(page, false);
  const layers: Buffer[] = [];
  for (let count = 1; count <= 5; count++) {
    await place(page, 2, 2, count);
    await page.mouse.move(10, 10);
    layers.push(await page.locator('canvas').screenshot());
  }
  for (let layer = 1; layer <= 5; layer++) {
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.getByRole('button', { name: 'Все слои', exact: true }).click();
    for (let hidden = layer + 1; hidden <= 5; hidden++)
      await page.getByRole('button', { name: 'Слой ' + hidden, exact: true }).click();
    await page.getByRole('button', { name: 'Вид', exact: true }).click();
    await page.mouse.move(10, 10);
    await page.waitForTimeout(300);
    const sliced = await page
      .locator('canvas')
      .screenshot({ path: testInfo.outputPath(`layer-${layer}.png`) });
    expect(await screenshotDifference(page, layers[layer - 1], sliced)).toBeLessThan(0.002);
    await expect(page.getByTestId('move-count')).toHaveText('5 / 125');
  }
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.getByRole('button', { name: 'Все слои', exact: true }).click();
  await page.getByRole('button', { name: 'Вид', exact: true }).click();
  await page.mouse.move(10, 10);
  await page.waitForTimeout(300);
  expect(
    await screenshotDifference(page, layers[4], await page.locator('canvas').screenshot()),
  ).toBeLessThan(0.002);
  expect(errors).toEqual([]);
});
