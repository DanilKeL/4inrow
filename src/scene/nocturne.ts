import { CanvasTexture, SRGBColorSpace, type BufferGeometry, Float32BufferAttribute } from 'three';
import type { SkinPalette } from '../skins/catalog';

type Painter = CanvasRenderingContext2D;
export type NocturneTextures = ReturnType<typeof makeNocturneTextures>;
function canvas(width: number, height = width) {
  const element = document.createElement('canvas');
  element.width = width;
  element.height = height;
  const context = element.getContext('2d')!;
  return { element, context };
}
function texture(element: HTMLCanvasElement, color = true) {
  const map = new CanvasTexture(element);
  if (color) map.colorSpace = SRGBColorSpace;
  map.anisotropy = 4;
  return map;
}
function circle(c: Painter, x: number, y: number, radius: number) {
  c.beginPath();
  c.arc(x, y, radius, 0, Math.PI * 2);
  c.stroke();
}
function star(c: Painter, x: number, y: number, size: number) {
  c.beginPath();
  c.moveTo(x, y - size);
  c.quadraticCurveTo(x + size * 0.18, y - size * 0.18, x + size, y);
  c.quadraticCurveTo(x + size * 0.18, y + size * 0.18, x, y + size);
  c.quadraticCurveTo(x - size * 0.18, y + size * 0.18, x - size, y);
  c.quadraticCurveTo(x - size * 0.18, y - size * 0.18, x, y - size);
  c.fill();
}
function rosette(c: Painter, x: number, y: number, radius: number, petals = 12) {
  c.save();
  c.translate(x, y);
  for (let i = 0; i < petals; i++) {
    c.rotate((Math.PI * 2) / petals);
    c.beginPath();
    c.moveTo(0, 0);
    c.bezierCurveTo(-radius * 0.36, -radius * 0.48, -radius * 0.24, -radius * 0.82, 0, -radius);
    c.bezierCurveTo(radius * 0.24, -radius * 0.82, radius * 0.36, -radius * 0.48, 0, 0);
    c.stroke();
  }
  circle(c, 0, 0, radius * 0.19);
  c.restore();
}
function branch(c: Painter, x: number, y: number, angle: number, length: number) {
  c.save();
  c.translate(x, y);
  c.rotate(angle);
  c.beginPath();
  c.moveTo(0, 0);
  c.bezierCurveTo(length * 0.2, -length * 0.14, length * 0.7, length * 0.14, length, 0);
  c.stroke();
  for (let i = 1; i < 10; i++) {
    const px = (length * i) / 11;
    const bend = Math.sin((i / 11) * Math.PI * 2) * length * -0.025;
    for (const side of [-1, 1]) {
      c.beginPath();
      c.moveTo(px - 5, bend);
      c.bezierCurveTo(
        px + 5,
        bend + side * 17,
        px + 15,
        bend + side * 23,
        px + 22,
        bend + side * 23,
      );
      c.bezierCurveTo(px + 23, bend + side * 10, px + 10, bend + side * 6, px - 5, bend);
      c.stroke();
      c.beginPath();
      c.moveTo(px, bend);
      c.lineTo(px + 18, bend + side * 19);
      c.stroke();
    }
  }
  c.restore();
}
function grain(c: Painter, width: number, height: number) {
  let seed = 804;
  for (let i = 0; i < 6500; i++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const x = (seed / 4294967296) * width;
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const y = (seed / 4294967296) * height;
    c.fillStyle = i % 2 ? 'rgba(255,255,255,.025)' : 'rgba(0,0,0,.02)';
    c.fillRect(x, y, 1, 1);
  }
}
function board(palette: SkinPalette) {
  const { element, context: c } = canvas(1024);
  c.fillStyle = palette.board.body;
  c.fillRect(0, 0, 1024, 1024);
  const glaze = c.createLinearGradient(0, 0, 1024, 1024);
  glaze.addColorStop(0, 'rgba(255,255,255,.055)');
  glaze.addColorStop(0.5, 'rgba(255,255,255,0)');
  glaze.addColorStop(1, 'rgba(0,0,0,.16)');
  c.fillStyle = glaze;
  c.fillRect(0, 0, 1024, 1024);
  grain(c, 1024, 1024);
  c.strokeStyle = c.fillStyle = palette.accent;
  c.lineWidth = 1.8;
  for (const inset of [28, 38]) {
    c.beginPath();
    c.roundRect(inset, inset, 1024 - inset * 2, 1024 - inset * 2, 55);
    c.stroke();
  }
  // Four botanical cartouches frame a continuous astronomical engraving.
  for (let corner = 0; corner < 4; corner++) {
    c.save();
    c.translate(512, 512);
    c.rotate((corner * Math.PI) / 2);
    c.translate(-512, -512);
    rosette(c, 76, 76, 38, 8);
    branch(c, 102, 67, 0, 243);
    branch(c, 67, 102, Math.PI / 2, 243);
    star(c, 512, 33, 8);
    c.restore();
  }
  c.save();
  c.translate(512, 512);
  c.globalAlpha = 0.57;
  for (const radius of [181, 304, 422]) circle(c, 0, 0, radius);
  for (const angle of [-0.58, 0.65]) {
    c.save();
    c.rotate(angle);
    c.beginPath();
    c.ellipse(0, 0, 444, 154, 0, 0, Math.PI * 2);
    c.stroke();
    c.restore();
  }
  for (let i = 0; i < 72; i++) {
    const a = (i * Math.PI) / 36;
    c.beginPath();
    c.moveTo(Math.cos(a) * 414, Math.sin(a) * 414);
    const r = i % 6 === 0 ? 398 : 409;
    c.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    c.stroke();
  }
  c.restore();
  // Each recessed seat receives its own celestial seal, readable between stacks.
  for (let y = 0; y < 5; y++)
    for (let x = 0; x < 5; x++) {
      const cx = 512 + (((x - 2) * 1.09) / 6.09) * 1024;
      const cy = 512 + (((y - 2) * 1.09) / 6.09) * 1024;
      c.save();
      c.translate(cx, cy);
      c.globalAlpha = 0.38;
      c.fillStyle = palette.board.body;
      c.beginPath();
      c.arc(0, 0, 62, 0, Math.PI * 2);
      c.fill();
      c.globalAlpha = 0.63;
      circle(c, 0, 0, 55);
      circle(c, 0, 0, 51);
      c.globalAlpha = 0.78;
      rosette(c, 0, 0, 31, (x + y) % 2 ? 8 : 12);
      for (let i = 0; i < 8; i++) {
        const a = (i * Math.PI) / 4;
        star(c, Math.cos(a) * 44, Math.sin(a) * 44, i % 2 ? 2 : 3.3);
      }
      c.restore();
    }
  c.globalAlpha = 0.7;
  c.fillStyle = palette.accent;
  const points = [
    [230, 112],
    [386, 254],
    [578, 203],
    [799, 356],
    [857, 580],
    [672, 786],
    [362, 837],
    [159, 654],
  ];
  c.beginPath();
  points.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y)));
  c.stroke();
  for (const [x, y] of points) star(c, x, y, 7);
  c.globalAlpha = 1;
  const metal = canvas(1024);
  const pixels = c.getImageData(0, 0, 1024, 1024);
  for (let i = 0; i < pixels.data.length; i += 4) {
    // Gold ink reflects light; the midnight enamel remains softly polished.
    const mask = Math.max(24, Math.min(255, (pixels.data[i] - 35) * 1.7));
    pixels.data[i] = pixels.data[i + 1] = pixels.data[i + 2] = mask;
  }
  metal.context.putImageData(pixels, 0, 0);
  return { surface: texture(element), metal: texture(metal.element, false) };
}
function cap(palette: SkinPalette, dark: boolean) {
  const { element, context: c } = canvas(512);
  const colors = dark ? palette.dark : palette.light;
  c.fillStyle = colors.cap;
  c.fillRect(0, 0, 512, 512);
  grain(c, 512, 512);
  c.strokeStyle = c.fillStyle = dark ? palette.accent : colors.mark;
  c.lineWidth = 2.5;
  circle(c, 256, 256, 219);
  circle(c, 256, 256, 204);
  c.lineWidth = 1.6;
  for (let i = 0; i < 40; i++) {
    const angle = (i * Math.PI) / 20;
    star(c, 256 + Math.cos(angle) * 211, 256 + Math.sin(angle) * 211, i % 5 ? 2 : 4);
  }
  if (dark) {
    // A drawn crescent with fine orbital lines, rather than an icon decal.
    c.beginPath();
    c.moveTo(296, 164);
    c.bezierCurveTo(166, 124, 133, 331, 259, 352);
    c.bezierCurveTo(207, 302, 207, 206, 296, 164);
    c.closePath();
    c.fill();
    c.globalAlpha = 0.55;
    circle(c, 256, 256, 142);
    c.globalAlpha = 1;
    for (const [x, y, size] of [
      [320, 251, 22],
      [286, 306, 9],
      [304, 208, 8],
      [346, 307, 5],
    ])
      star(c, x, y, size);
    c.beginPath();
    c.moveTo(283, 300);
    c.lineTo(320, 251);
    c.lineTo(304, 208);
    c.stroke();
  } else {
    c.lineWidth = 4.8;
    rosette(c, 256, 256, 129, 12);
    circle(c, 256, 256, 58);
    circle(c, 256, 256, 49);
    c.lineWidth = 3;
    for (let i = 0; i < 24; i++) {
      const a = (i * Math.PI) / 12;
      c.beginPath();
      c.moveTo(256 + Math.cos(a) * 140, 256 + Math.sin(a) * 140);
      c.lineTo(256 + Math.cos(a) * (i % 2 ? 153 : 173), 256 + Math.sin(a) * (i % 2 ? 153 : 173));
      c.stroke();
    }
    star(c, 256, 256, 30);
  }
  return texture(element);
}
function body(palette: SkinPalette, dark: boolean) {
  const { element, context: c } = canvas(512, 256);
  c.fillStyle = (dark ? palette.dark : palette.light).body;
  c.fillRect(0, 0, 512, 256);
  grain(c, 512, 256);
  c.strokeStyle = c.fillStyle = dark ? palette.accent : palette.light.mark;
  c.lineWidth = 2;
  for (const y of [32, 40, 215, 223]) {
    c.beginPath();
    c.moveTo(0, y);
    c.lineTo(512, y);
    c.stroke();
  }
  c.lineWidth = 1.25;
  for (let i = -1; i < 9; i++) {
    c.save();
    c.translate(i * 64 + 32, 128);
    rosette(c, 0, 0, 29, 6);
    c.beginPath();
    c.moveTo(-32, 0);
    c.quadraticCurveTo(-18, -45, 0, -40);
    c.quadraticCurveTo(18, -45, 32, 0);
    c.stroke();
    c.beginPath();
    c.moveTo(-32, 0);
    c.quadraticCurveTo(-18, 45, 0, 40);
    c.quadraticCurveTo(18, 45, 32, 0);
    c.stroke();
    c.restore();
  }
  return texture(element);
}
export function makeNocturneTextures(palette: SkinPalette) {
  const artwork = board(palette);
  return {
    board: artwork.surface,
    metal: artwork.metal,
    darkBody: body(palette, true),
    darkCap: cap(palette, true),
    lightBody: body(palette, false),
    lightCap: cap(palette, false),
  };
}
export function disposeNocturneTextures(textures: NocturneTextures | null) {
  if (textures) for (const map of Object.values(textures)) map.dispose();
}
export function planarBoardGeometry(source: BufferGeometry) {
  const geometry = source.clone();
  const positions = geometry.getAttribute('position');
  const uv = new Float32Array(positions.count * 2);
  for (let i = 0; i < positions.count; i++) {
    uv[i * 2] = (positions.getX(i) + 3.045) / 6.09;
    uv[i * 2 + 1] = (positions.getZ(i) + 3.045) / 6.09;
  }
  geometry.setAttribute('uv', new Float32BufferAttribute(uv, 2));
  return geometry;
}
