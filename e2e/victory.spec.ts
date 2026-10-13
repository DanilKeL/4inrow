import { test, expect, type Page } from '@playwright/test';
import { columnPosition, openGame, place } from './helpers';

interface Sample {
  elapsedMs: number;
  renderedFallOffset: number;
  renderedWinningLines: number;
  canvasHeight: number;
  controls: boolean;
  cameraLocked?: boolean;
  cameraPosition?: number[];
  cameraTarget?: number[];
  cameraPixelScale?: number;
}
interface Timeline {
  early: Sample | null;
  settled: Sample | null;
  dragged: Sample | null;
  drop: Sample | null;
  line: Sample | null;
}

async function observeVictory(page: Page) {
  await page.evaluate(() => {
    const timeline: Timeline = {
      early: null,
      settled: null,
      dragged: null,
      drop: null,
      line: null,
    };
    (window as unknown as { victoryTimeline: Timeline }).victoryTimeline = timeline;
    const sample = () => {
      const scene = window.__fourScene?.getVictoryPresentationState();
      if (scene) {
        const frame = {
          ...scene,
          canvasHeight: document.querySelector('canvas')!.getBoundingClientRect().height,
          controls: Boolean(document.querySelector('aside button')),
        };
        if (!timeline.early && scene.elapsedMs >= 100) timeline.early = frame;
        if (!timeline.settled && scene.elapsedMs >= 900) {
          timeline.settled = frame;
          const canvas = document.querySelector('canvas')!;
          canvas.dispatchEvent(
            new PointerEvent('pointerdown', {
              pointerId: 10,
              pointerType: 'mouse',
              clientX: 120,
              clientY: 220,
              buttons: 1,
              button: 0,
              bubbles: true,
            }),
          );
          canvas.dispatchEvent(
            new PointerEvent('pointermove', {
              pointerId: 10,
              pointerType: 'mouse',
              clientX: 260,
              clientY: 320,
              buttons: 1,
              bubbles: true,
            }),
          );
          canvas.dispatchEvent(
            new PointerEvent('pointerup', {
              pointerId: 10,
              pointerType: 'mouse',
              clientX: 260,
              clientY: 320,
              buttons: 0,
              bubbles: true,
            }),
          );
          canvas.dispatchEvent(
            new WheelEvent('wheel', { deltaY: -250, bubbles: true, cancelable: true }),
          );
        }
        if (!timeline.dragged && scene.elapsedMs >= 1400) timeline.dragged = frame;
        if (!timeline.drop && scene.elapsedMs >= 600) timeline.drop = frame;
        if (!timeline.line && scene.elapsedMs >= 2700) timeline.line = frame;
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
  expect(timeline.early!.renderedFallOffset).toBeCloseTo(2.2);
  expect(timeline.early!.cameraLocked).toBe(true);
  expect(timeline.drop!.cameraLocked).toBe(true);
  expect(timeline.early!.cameraPosition).not.toEqual(timeline.drop!.cameraPosition);
  expect(timeline.settled!.cameraPosition).toEqual(timeline.dragged!.cameraPosition);
  expect(timeline.dragged!.cameraLocked).toBe(true);
  expect(timeline.line!.cameraLocked).toBe(false);
  expect(timeline.line!.cameraPixelScale).toBeCloseTo(timeline.settled!.cameraPixelScale!, 5);
  for (const [index, value] of timeline.settled!.cameraPosition!.entries())
    expect(timeline.line!.cameraPosition![index]).toBeCloseTo(value, 6);
  expect(timeline.drop!.renderedFallOffset).toBeGreaterThan(0.05);
  expect(timeline.drop!.renderedWinningLines).toBe(0);
  expect(Math.abs(timeline.line!.renderedFallOffset)).toBeLessThan(0.02);
  expect(timeline.line!.renderedWinningLines).toBeGreaterThanOrEqual(1);
  expect(timeline.line!.controls).toBe(false);
  expect(timeline.line!.canvasHeight).toBeCloseTo(timeline.drop!.canvasHeight, 0);
  await expect(page.getByRole('heading', { name: title })).toBeVisible();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByTestId('ranked-result')).toHaveCount(0);
  const finalFrame = await page.evaluate(() => window.__fourScene!.getVictoryPresentationState()!);
  expect(finalFrame.cameraPixelScale).toBeCloseTo(timeline.settled!.cameraPixelScale!, 5);
  for (const [index, value] of timeline.settled!.cameraPosition!.entries())
    expect(finalFrame.cameraPosition![index]).toBeCloseTo(value, 6);
  const finishedPose = await page.evaluate(
    () => window.__fourScene!.getVictoryPresentationState()!.cameraPosition,
  );
  await page.waitForTimeout(350);
  expect(
    await page.evaluate(() => window.__fourScene!.getVictoryPresentationState()!.cameraPosition),
  ).toEqual(finishedPose);
  const bounds = await page.getByTestId('game-canvas').boundingBox();
  await page.mouse.move(bounds!.x + bounds!.width / 2, bounds!.y + bounds!.height / 2);
  await page.mouse.down();
  await page.mouse.move(bounds!.x + bounds!.width / 2 + 65, bounds!.y + bounds!.height / 2, {
    steps: 8,
  });
  await page.mouse.up();
  expect(
    await page.evaluate(() => window.__fourScene!.getVictoryPresentationState()!.cameraPosition),
  ).not.toEqual(finishedPose);
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
