import { describe, expect, it } from 'vitest';
import { displayedHeight, visibleLineSegments } from './layers';

describe('independent layer visibility', () => {
  it('keeps floating layers at their actual height and picks only visible occupied levels', () => {
    expect(displayedHeight(5, [1, 3, 4])).toBe(5);
    expect(displayedHeight(3, [1, 3, 4])).toBe(2);
    expect(displayedHeight(1, [1, 3, 4])).toBe(0);
    expect(displayedHeight(5, [0, 2])).toBe(3);
    expect(displayedHeight(5, [])).toBe(0);
  });
  it('does not bridge hidden levels with a winning line', () => {
    const line = [0, 1, 2, 3].map((z) => ({ x: 2, y: 2, z }));
    expect(visibleLineSegments(line, [0, 2, 3])).toEqual([[line[2], line[3]]]);
    expect(visibleLineSegments(line, [0, 2])).toEqual([]);
    const horizontal = line.map((p, x) => ({ ...p, x, z: 2 }));
    expect(visibleLineSegments(horizontal, [2])).toHaveLength(3);
    expect(visibleLineSegments(horizontal, [1])).toEqual([]);
  });
});
