import { test, expect } from '@playwright/test';

for (const mobile of [false, true]) {
  test(`backdrop ${mobile ? 'touch' : 'click'} closes the window without activating the menu underneath`, async ({
    browser,
    baseURL,
  }) => {
    const context = await browser.newContext({
      baseURL,
      viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 900 },
      hasTouch: mobile,
      isMobile: mobile,
    });
    const page = await context.newPage();
    const errors: string[] = [];
    page.on('pageerror', (error) => errors.push(error.message));
    try {
      await page.goto('/');
      const targets = [
        page.getByRole('button', { name: /Аккаунт:/ }),
        page.getByRole('button', { name: 'Как играть', exact: true }),
        page.getByRole('button', { name: /^(Выключить|Включить) звук$/ }),
        page.getByRole('button', { name: 'Настройки', exact: true }),
        page.getByRole('button', { name: 'Уровни', exact: true }),
      ];
      const soundBefore = await targets[2].getAttribute('aria-label');
      for (const target of targets) {
        await page.getByRole('button', { name: 'Настройки', exact: true }).click();
        const dialog = page.getByRole('dialog', { name: 'Настройки' });
        await expect(dialog).toBeVisible();
        const bounds = (await target.boundingBox())!;
        const windowBounds = (await dialog.boundingBox())!;
        const x = bounds.x + bounds.width / 2,
          y = bounds.y + bounds.height / 2;
        // Test coordinates behind the backdrop, not controls inside the modal.
        if (
          x >= windowBounds.x &&
          x <= windowBounds.x + windowBounds.width &&
          y >= windowBounds.y &&
          y <= windowBounds.y + windowBounds.height
        ) {
          await dialog.getByRole('button', { name: 'Закрыть', exact: true }).click();
          continue;
        }
        if (mobile) await page.touchscreen.tap(x, y);
        else await page.mouse.click(x, y);
        await expect(page.getByRole('dialog')).toHaveCount(0);
        // Legacy touch browsers can dispatch a compatibility click after a short delay.
        await page.waitForTimeout(350);
        await expect(page.getByRole('dialog')).toHaveCount(0);
        await expect(page.getByRole('region', { name: 'Режимы игры' })).toBeVisible();
        await expect(targets[2]).toHaveAttribute('aria-label', soundBefore!);
      }
      // A separate deliberate tap on the menu must still work after dismissing.
      const help = page.getByRole('button', { name: 'Как играть', exact: true });
      if (mobile) await help.tap();
      else await help.click();
      const tutorial = page.getByRole('dialog', { name: 'Как играть' });
      await expect(tutorial).toBeVisible();
      const settings = (await page
        .getByRole('button', { name: 'Настройки', exact: true })
        .boundingBox())!;
      if (mobile)
        await page.touchscreen.tap(
          settings.x + settings.width / 2,
          settings.y + settings.height / 2,
        );
      else
        await page.mouse.click(settings.x + settings.width / 2, settings.y + settings.height / 2);
      await expect(page.getByRole('dialog')).toHaveCount(0);
      expect(errors).toEqual([]);
    } finally {
      await context.close();
    }
  });
}
