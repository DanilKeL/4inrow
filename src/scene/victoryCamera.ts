import type { PerspectiveCamera } from 'three';
import type { OrbitControls } from 'three-stdlib';

export interface VictoryFraming {
  height: number;
  fov: number;
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
