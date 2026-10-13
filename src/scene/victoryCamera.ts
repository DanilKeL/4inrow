import { Box3, Spherical, Vector3, type PerspectiveCamera } from 'three';
import type { OrbitControls } from 'three-stdlib';

export interface VictoryFraming {
  height: number;
  fov: number;
}

/** Fit every winning chip, including the final chip's drop, into the actual frustum. */
export function fitVictoryCamera(
  points: readonly Vector3[],
  last: Vector3,
  pose: Spherical,
  fov: number,
  aspect: number,
) {
  const target = new Box3().setFromPoints([...points]).getCenter(new Vector3());
  const backward = new Vector3().setFromSpherical(new Spherical(1, pose.phi, pose.theta));
  const right = new Vector3(0, 1, 0).cross(backward).normalize();
  const up = backward.clone().cross(right);
  // Leave room around the chip rims and line, rather than fitting just their centers.
  const vertical = Math.tan((fov * Math.PI) / 360) * 0.8;
  const horizontal = vertical * aspect;
  let radius = pose.radius;
  for (const point of [...points, last.clone().add(new Vector3(0, 2.2, 0))]) {
    for (const x of [-0.42, 0.42])
      for (const y of [-0.3, 0.3])
        for (const z of [-0.42, 0.42]) {
          const offset = point
            .clone()
            .add(new Vector3(x, y, z))
            .sub(target);
          const depth = offset.dot(backward);
          radius = Math.max(
            radius,
            depth + Math.abs(offset.dot(right)) / horizontal,
            depth + Math.abs(offset.dot(up)) / vertical,
            depth + 0.1,
          );
        }
  }
  return { target, pose: new Spherical(radius, pose.phi, pose.theta) };
}

/** Keep the same world-to-pixel scale when inline results resize the canvas. */
export function preserveVictoryFraming(
  camera: PerspectiveCamera,
  height: number,
  frame: VictoryFraming,
) {
  if (height <= 0 || frame.height <= 0) return;
  const fov =
    (360 / Math.PI) * Math.atan((Math.tan((frame.fov * Math.PI) / 360) * height) / frame.height);
  if (Math.abs(camera.fov - fov) > 1e-9) {
    camera.fov = fov;
    camera.updateProjectionMatrix();
  }
}

/** Hand the exact cinematic pose to OrbitControls without its distance clamp snapping it. */
export function releaseVictoryOrbit(controls: OrbitControls) {
  const radius = controls.object.position.distanceTo(controls.target);
  controls.minDistance = Math.min(7, radius);
  controls.maxDistance = Math.max(23, radius);
  controls.enableDamping = false;
  controls.update();
  controls.enableDamping = true;
  controls.enabled = true;
}
