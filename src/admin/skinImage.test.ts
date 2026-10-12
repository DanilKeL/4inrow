import { describe, expect, it } from 'vitest';
import { imageDimensions, rasterMime } from './skinImage';

describe('skin image import boundaries', () => {
  it('recognizes supported file signatures and rejects SVG regardless of a filename', () => {
    expect(rasterMime(Uint8Array.of(137, 80, 78, 71, 13, 10, 26, 10))).toBe('image/png');
    expect(rasterMime(Uint8Array.of(255, 216, 255))).toBe('image/jpeg');
    expect(rasterMime(new TextEncoder().encode('RIFF0000WEBP'))).toBe('image/webp');
    expect(
      rasterMime(new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg">')),
    ).toBeNull();
    expect(rasterMime(new TextEncoder().encode('RIFF0000AVI '))).toBeNull();
    expect(rasterMime(Uint8Array.of(137, 80))).toBeNull();
  });
  it('preserves portrait and landscape proportions, never enlarges small sprites', () => {
    expect(imageDimensions(4000, 2000)).toEqual({ width: 1024, height: 512 });
    expect(imageDimensions(1200, 2400)).toEqual({ width: 512, height: 1024 });
    expect(imageDimensions(48, 64)).toEqual({ width: 48, height: 64 });
    expect(imageDimensions(16384, 1)).toEqual({ width: 1024, height: 1 });
  });
  it('rejects invalid or excessive source dimensions before rasterization', () => {
    for (const [width, height] of [
      [0, 4],
      [4, 0],
      [Infinity, 2],
      [NaN, 2],
      [16385, 100],
    ])
      expect(() => imageDimensions(width, height)).toThrow();
  });
});
