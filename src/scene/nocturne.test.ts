import { expect, it } from 'vitest';
import { BufferGeometry, Float32BufferAttribute } from 'three';
import { planarBoardGeometry } from './nocturne';
it('maps the unwrapped board in XZ without modifying cached source geometry', () => {
  const source = new BufferGeometry();
  source.setAttribute(
    'position',
    new Float32BufferAttribute([-3.045, 0.162, -3.045, 3.045, 0.162, 3.045, 0, 0.104, 0], 3),
  );
  const mapped = planarBoardGeometry(source);
  expect(source.getAttribute('uv')).toBeUndefined();
  const uv = mapped.getAttribute('uv');
  expect(uv.getX(0)).toBeCloseTo(0);
  expect(uv.getY(0)).toBeCloseTo(0);
  expect(uv.getX(1)).toBeCloseTo(1);
  expect(uv.getY(1)).toBeCloseTo(1);
  expect(uv.getX(2)).toBe(0.5);
  expect(uv.getY(2)).toBe(0.5);
  expect(mapped.getAttribute('position').array).toEqual(source.getAttribute('position').array);
  mapped.dispose();
  source.dispose();
});
