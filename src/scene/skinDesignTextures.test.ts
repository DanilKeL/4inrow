import { expect, it } from 'vitest';
import { blankDesign, motifLayer } from '../skins/design';
import { layerPositions, surfaceDrawingSignature } from './skinDesignTextures';

it('retains drawing identity when only material reflectivity changes', () => {
  const surface = blankDesign().surfaces.board;
  const original = surfaceDrawingSignature('#123456', surface);
  expect(surfaceDrawingSignature('#123456', { ...surface, roughness: 0.8, metalness: 0.4 })).toBe(
    original,
  );
  expect(surfaceDrawingSignature('#654321', surface)).not.toBe(original);
  expect(surfaceDrawingSignature('#123456', { ...surface, layers: [motifLayer('moon')] })).not.toBe(
    original,
  );
});

it('places a motif at its configured position and mirrors corner cartouches', () => {
  const layer = { ...motifLayer('lotus'), x: 0.25, y: 0.8, rotation: 35 };
  expect(layerPositions(layer, 1024, 512)).toEqual([{ x: 256, y: 409.6, rotation: 35 }]);
  const corners = layerPositions(
    { ...layer, x: 0.5, y: 0.5, size: 0.2, placement: 'corners' },
    1024,
    1024,
  );
  expect(corners).toHaveLength(4);
  expect(corners[0].x + corners[1].x).toBe(1024);
  expect(corners[0].y + corners[3].y).toBe(1024);
  expect(corners.map((point) => point.rotation)).toEqual([35, 125, 215, 305]);
});

it('bounds grid complexity independently of tiny motif scale and wraps sidewall decoration', () => {
  const layer = { ...motifLayer('diamond'), size: 0.05, placement: 'grid' as const };
  for (const [width, height] of [
    [1024, 1024],
    [512, 256],
  ]) {
    const positions = layerPositions(layer, width, height);
    expect(positions.length).toBeLessThanOrEqual(96);
    expect(positions.every(({ x, y }) => x >= 0 && x <= width && y >= 0 && y <= height)).toBe(true);
  }
});
