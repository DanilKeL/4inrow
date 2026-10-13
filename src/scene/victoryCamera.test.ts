import { describe, expect, it } from 'vitest';
import { PerspectiveCamera, Spherical, Vector3 } from 'three';
import { OrbitControls } from 'three-stdlib';
import { fitVictoryCamera, preserveVictoryFraming, releaseVictoryOrbit } from './victoryCamera';
import { DIRECTIONS } from '../game/core';

describe('victory line framing', () => {
  it.each([0.35, 0.6, 1, 2.8])(
    'fits all line directions and the falling chip at aspect %s, regardless of prior zoom',
    (aspect) => {
      for (const direction of DIRECTIONS) {
        const points = Array.from(
          { length: 5 },
          (_, index) =>
            new Vector3(
              ((direction.x < 0 ? 4 : 0) + index * direction.x - 2) * 1.09,
              0.365 + ((direction.z < 0 ? 4 : 0) + index * direction.z) * 0.5,
              ((direction.y < 0 ? 4 : 0) + index * direction.y - 2) * 1.09,
            ),
        );
        for (const radius of [7, 23])
          for (const theta of [0, 0.7, 2.6]) {
            const framed = fitVictoryCamera(
              points,
              points.at(-1)!,
              new Spherical(radius, 0.82, theta),
              35,
              aspect,
            );
            const camera = new PerspectiveCamera(35, aspect, 0.1, 100);
            camera.position.copy(framed.target).add(new Vector3().setFromSpherical(framed.pose));
            camera.lookAt(framed.target);
            camera.updateMatrixWorld();
            for (const point of [
              ...points,
              points
                .at(-1)!
                .clone()
                .add(new Vector3(0, 2.2, 0)),
            ])
              for (const x of [-0.42, 0.42])
                for (const y of [-0.3, 0.3])
                  for (const z of [-0.42, 0.42]) {
                    const projected = point
                      .clone()
                      .add(new Vector3(x, y, z))
                      .project(camera);
                    expect(Math.abs(projected.x)).toBeLessThanOrEqual(0.8000001);
                    expect(Math.abs(projected.y)).toBeLessThanOrEqual(0.8000001);
                    expect(projected.z).toBeGreaterThan(-1);
                    expect(projected.z).toBeLessThan(1);
                  }
          }
      }
    },
  );

  it('frames simultaneous crossing winning lines together', () => {
    const points = [
      new Vector3(-2.18, 2.365, 0),
      new Vector3(2.18, 2.365, 0),
      new Vector3(0, 2.365, -2.18),
      new Vector3(0, 2.365, 2.18),
    ];
    const framed = fitVictoryCamera(
      points,
      new Vector3(0, 2.365, 0),
      new Spherical(7, 0.82, 0.6),
      35,
      0.5,
    );
    const camera = new PerspectiveCamera(35, 0.5);
    camera.position.copy(framed.target).add(new Vector3().setFromSpherical(framed.pose));
    camera.lookAt(framed.target);
    camera.updateMatrixWorld();
    for (const point of points) {
      const projected = point.clone().project(camera);
      expect(Math.abs(projected.x)).toBeLessThan(0.8);
      expect(Math.abs(projected.y)).toBeLessThan(0.8);
    }
  });
});

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
