import type { Position } from '../game/core';

export function displayedHeight(height: number, layers: readonly number[]): number {
  return Math.max(0, ...layers.filter((z) => z < height).map((z) => z + 1));
}

// Do not connect winning pieces across a hidden layer.
export function visibleLineSegments(line: Position[], layers: readonly number[]): Position[][] {
  return line
    .slice(1)
    .flatMap((point, i) =>
      layers.includes(line[i].z) && layers.includes(point.z) ? [[line[i], point]] : [],
    );
}
