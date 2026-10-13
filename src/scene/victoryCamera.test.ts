import { describe, expect, it } from 'vitest';
import { PerspectiveCamera, Vector3 } from 'three';
import { OrbitControls } from 'three-stdlib';
import { preserveVictoryFraming, releaseVictoryOrbit } from './victoryCamera';

describe('victory camera handoff', () => {
  it('keeps projected board size as the mobile result buttons take space, and restores it for a new game', () => {
    const camera = new PerspectiveCamera(35, 390 / 654);
    camera.position.set(0, 8, 10);
    camera.lookAt(0, 0, 0);
    camera.updateMatrixWorld();
    const position = camera.position.clone();
    const projectedWidth = (height: number) => {
      const left = new Vector3(-1.6, 0, 0).project(camera);
      const right = new Vector3(1.6, 0, 0).project(camera);
      return ((right.x - left.x) * height * camera.aspect) / 2;
    };
    const before = projectedWidth(654);
    for (const height of [540, 510, 530, 654]) {
      camera.aspect = 390 / height;
      preserveVictoryFraming(camera, height, { height: 654, fov: 35 });
      expect(projectedWidth(height)).toBeCloseTo(before, 8);
      expect(camera.position.distanceTo(position)).toBe(0);
    }
    expect(camera.fov).toBeCloseTo(35, 10);
  });
  it.each([4, 16, 29])(
    'keeps a cinematic distance of %s when controls resume, then permits rotation',
    (radius) => {
      const camera = new PerspectiveCamera(35, 1);
      const controls = new OrbitControls(camera);
      controls.minDistance = 7;
      controls.maxDistance = 23;
      controls.enabled = false;
      controls.target.set(1, 0.8, -1);
      camera.position
        .copy(controls.target)
        .add(new Vector3(1, 1, 1).normalize().multiplyScalar(radius));
      const position = camera.position.clone();
      const target = controls.target.clone();
      releaseVictoryOrbit(controls);
      controls.update();
      expect(camera.position.distanceTo(position)).toBeLessThan(1e-8);
      expect(controls.target.distanceTo(target)).toBe(0);
      expect(controls.enabled).toBe(true);
      const oldAngle = controls.getAzimuthalAngle();
      controls.setAzimuthalAngle(oldAngle + 0.2);
      controls.update();
      expect(camera.position.distanceTo(position)).toBeGreaterThan(0.01);
      expect(camera.position.distanceTo(controls.target)).toBeCloseTo(radius, 8);
      controls.dispose();
    },
  );
});
