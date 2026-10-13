import { test, expect, type Page } from '@playwright/test';
import { columnPosition, openGame, place } from './helpers';

interface Sample {
  elapsedMs: number;
  renderedFallOffset: number;
  renderedWinningLines: number;
  canvasHeight: number;
  controls: boolean;
}
interface Timeline {
  drop: Sample | null;
  line: Sample | null;
}

async function observeVictory(page: Page) {
  await page.evaluate(() => {
    const timeline: Timeline = { drop: null, line: null };
    (window as unknown as { victoryTimeline: Timeline }).victoryTimeline = timeline;
    const sample = () => {
      const scene = window.__fourScene?.getVictoryPresentationState();
      if (scene) {
        const frame = {
          ...scene,
          canvasHeight: document.querySelector('canvas')!.getBoundingClientRect().height,
          controls: Boolean(document.querySelector('aside button')),
        };
        if (!timeline.drop && scene.elapsedMs >= 600) timeline.drop = frame;
        if (!timeline.line && scene.elapsedMs >= 2000) timeline.line = frame;
      }
      if (!timeline.line) requestAnimationFrame(sample);
    };
    requestAnimationFrame(sample);
  });
}

async function checkVictory(page: Page, title: RegExp | string) {
  await page.waitForFunction(() =>
    Boolean((window as unknown as { victoryTimeline: Timeline }).victoryTimeline.line),
  );
  const timeline = await page.evaluate(
    () => (window as unknown as { victoryTimeline: Timeline }).victoryTimeline,
  );
  expect(timeline.drop!.renderedFallOffset).toBeGreaterThan(0.05);
  expect(timeline.drop!.renderedWinningLines).toBe(0);
  expect(Math.abs(timeline.line!.renderedFallOffset)).toBeLessThan(0.02);
  expect(timeline.line!.renderedWinningLines).toBeGreaterThanOrEqual(1);
  expect(timeline.line!.controls).toBe(false);
  expect(timeline.line!.canvasHeight).toBeCloseTo(timeline.drop!.canvasHeight, 0);
  await expect(page.getByRole('heading', { name: title })).toBeVisible();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByTestId('ranked-result')).toHaveCount(0);
}

test('a local win shows the slow final move on mobile, keeping the board size and inline result', async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openGame(page);
  for (const [index, [x, y]] of [
    [0, 0],
    [0, 4],
    [1, 0],
    [1, 4],
    [2, 0],
    [2, 4],
  ].entries())
    await place(page, x, y, index + 1);
  await observeVictory(page);
  const point = await columnPosition(page, 3, 0);
  await page.mouse.click(point.screenX, point.screenY);
  await checkVictory(page, /Победа:/);
  await page.getByRole('button', { name: 'Ещё партия', exact: true }).click();
  await expect(page.getByTestId('move-count')).toHaveText('0 / 125');
  await expect(page.getByTestId('victory-presentation')).toHaveCount(0);
});

test('a real bot winning reply uses the same presentation and replay does not restart it', async ({
  page,
}) => {
  await openGame(page, 'ai');
  await observeVictory(page);
  await page.evaluate(async () => {
    // Seed a legal tactical position, then let the real worker finish the game.
    const storePath = '/src/store/gameStore.ts';
    const corePath = '/src/game/core/index.ts';
    const { useGame } = await import(storePath);
    const { replay } = await import(corePath);
    useGame.setState({
      game: replay([
        { x: 0, y: 4 },
        { x: 0, y: 0 },
        { x: 1, y: 4 },
        { x: 1, y: 0 },
        { x: 2, y: 4 },
        { x: 2, y: 0 },
        { x: 4, y: 4 },
      ]),
      phase: 'playing',
    });
    useGame.getState().settle();
  });
  await checkVictory(page, 'Победа: FOUR AI');
  await page.getByRole('button', { name: 'Повтор партии', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Повтор партии', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Завершить просмотр', exact: true }).click();
  const scene = await page.evaluate(() => window.__fourScene!.getVictoryPresentationState());
  expect(scene!.elapsedMs).toBeGreaterThan(3500);
  expect(Math.abs(scene!.renderedFallOffset)).toBeLessThan(0.02);
  await expect(page.getByRole('dialog')).toHaveCount(0);
});
