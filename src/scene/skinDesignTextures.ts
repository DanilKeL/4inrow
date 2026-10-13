import { CanvasTexture, SRGBColorSpace } from 'three';
import type { DesignLayer, Motif, SurfaceDesign, SurfaceName } from '../skins/design';

type Painter = CanvasRenderingContext2D;
type ImageLookup = (id: string) => HTMLImageElement | undefined;
type Drawing = Omit<SurfaceDesign, 'roughness' | 'metalness'> & { background: string };

export function surfaceDrawingSignature(background: string, design: SurfaceDesign) {
  return JSON.stringify({
    pattern: design.pattern,
    ink: design.ink,
    patternScale: design.patternScale,
    patternOpacity: design.patternOpacity,
    border: design.border,
    layers: design.layers,
    background,
  });
}

function circle(c: Painter, x: number, y: number, radius: number) {
  c.beginPath();
  c.arc(x, y, radius, 0, Math.PI * 2);
  c.stroke();
}

function star(c: Painter, x: number, y: number, radius: number) {
  c.beginPath();
  c.moveTo(x, y - radius);
  c.quadraticCurveTo(x + radius * 0.2, y - radius * 0.2, x + radius, y);
  c.quadraticCurveTo(x + radius * 0.2, y + radius * 0.2, x, y + radius);
  c.quadraticCurveTo(x - radius * 0.2, y + radius * 0.2, x - radius, y);
  c.quadraticCurveTo(x - radius * 0.2, y - radius * 0.2, x, y - radius);
  c.fill();
}

function rosette(c: Painter, radius: number, petals = 12) {
  c.save();
  for (let i = 0; i < petals; i++) {
    c.rotate((Math.PI * 2) / petals);
    c.beginPath();
    c.moveTo(0, 0);
    c.bezierCurveTo(-radius * 0.3, -radius * 0.4, -radius * 0.3, -radius * 0.78, 0, -radius);
    c.bezierCurveTo(radius * 0.3, -radius * 0.78, radius * 0.3, -radius * 0.4, 0, 0);
    c.stroke();
  }
  c.restore();
}

function branch(c: Painter, length: number, bend = 0) {
  c.beginPath();
  c.moveTo(0, 0);
  c.quadraticCurveTo(length * 0.5, bend, length, 0);
  c.stroke();
  for (let i = 1; i < 9; i++) {
    const x = (length * i) / 10;
    const y = 2 * (i / 10) * (1 - i / 10) * bend;
    for (const side of [-1, 1]) {
      c.beginPath();
      c.moveTo(x, y);
      c.bezierCurveTo(
        x + length * 0.06,
        y + side * length * 0.03,
        x + length * 0.08,
        y + side * length * 0.13,
        x + length * 0.13,
        y + side * length * 0.16,
      );
      c.bezierCurveTo(
        x + length * 0.03,
        y + side * length * 0.17,
        x - length * 0.03,
        y + side * length * 0.06,
        x,
        y,
      );
      c.stroke();
    }
  }
}

export function paintMotif(c: Painter, motif: Motif, size: number) {
  const r = size / 2;
  c.lineWidth = Math.max(1, size * 0.009);
  if (motif === 'heart') {
    c.save();
    c.beginPath();
    c.moveTo(0, r * 0.82);
    c.bezierCurveTo(-r * 0.28, r * 0.51, -r * 0.92, r * 0.12, -r * 0.86, -r * 0.35);
    c.bezierCurveTo(-r * 0.8, -r * 0.91, -r * 0.22, -r * 0.97, 0, -r * 0.51);
    c.bezierCurveTo(r * 0.22, -r * 0.97, r * 0.8, -r * 0.91, r * 0.86, -r * 0.35);
    c.bezierCurveTo(r * 0.92, r * 0.12, r * 0.28, r * 0.51, 0, r * 0.82);
    c.closePath();
    c.fill();
    c.strokeStyle = '#fff9f1';
    c.globalAlpha *= 0.5;
    c.lineWidth = size * 0.023;
    c.lineCap = 'round';
    c.beginPath();
    c.moveTo(-r * 0.65, -r * 0.22);
    c.bezierCurveTo(-r * 0.7, -r * 0.58, -r * 0.42, -r * 0.76, -r * 0.25, -r * 0.61);
    c.stroke();
    c.restore();
    return;
  }
  if (motif === 'bow') {
    c.save();
    for (const side of [-1, 1]) {
      c.save();
      c.scale(side, 1);
      c.beginPath();
      c.moveTo(0, 0);
      c.bezierCurveTo(r * 0.35, -r * 0.52, r * 0.96, -r * 0.7, r * 0.92, -r * 0.32);
      c.bezierCurveTo(r * 0.9, r * 0.2, r * 0.52, r * 0.32, 0, 0);
      c.closePath();
      c.fill();
      c.beginPath();
      c.moveTo(r * 0.02, r * 0.01);
      c.lineTo(r * 0.61, r * 0.76);
      c.lineTo(r * 0.61, r * 0.42);
      c.lineTo(r * 0.34, r * 0.52);
      c.lineTo(-r * 0.06, r * 0.07);
      c.closePath();
      c.fill();
      c.strokeStyle = '#fff1eb';
      c.globalAlpha *= 0.42;
      c.lineWidth = size * 0.012;
      c.beginPath();
      c.moveTo(r * 0.13, -r * 0.02);
      c.quadraticCurveTo(r * 0.52, -r * 0.27, r * 0.77, -r * 0.26);
      c.stroke();
      c.restore();
    }
    c.beginPath();
    c.ellipse(0, 0, r * 0.19, r * 0.23, 0, 0, Math.PI * 2);
    c.fill();
    c.restore();
    return;
  }
  if (motif === 'blossom') {
    c.save();
    for (let petal = 0; petal < 6; petal++) {
      c.rotate(Math.PI / 3);
      c.beginPath();
      c.ellipse(0, -r * 0.52, r * 0.28, r * 0.44, 0, 0, Math.PI * 2);
      c.fill();
    }
    c.fillStyle = '#e7bf7d';
    c.beginPath();
    c.arc(0, 0, r * 0.23, 0, Math.PI * 2);
    c.fill();
    c.restore();
    return;
  }
  if (motif === 'star') {
    star(c, 0, 0, r * 0.85);
    circle(c, 0, 0, r * 0.97);
    return;
  }
  if (motif === 'moon') {
    c.beginPath();
    c.moveTo(r * 0.35, -r * 0.78);
    c.bezierCurveTo(-r * 0.8, -r * 0.98, -r, r * 0.75, r * 0.1, r * 0.9);
    c.bezierCurveTo(-r * 0.35, r * 0.3, -r * 0.24, -r * 0.47, r * 0.35, -r * 0.78);
    c.fill();
    circle(c, 0, 0, r * 0.98);
    star(c, r * 0.6, -r * 0.03, r * 0.22);
    star(c, r * 0.39, r * 0.49, r * 0.075);
    star(c, r * 0.45, -r * 0.55, r * 0.075);
    return;
  }
  if (motif === 'sun') {
    rosette(c, r * 0.65);
    circle(c, 0, 0, r * 0.3);
    circle(c, 0, 0, r * 0.25);
    star(c, 0, 0, r * 0.16);
    for (let i = 0; i < 32; i++) {
      const a = (i * Math.PI) / 16;
      c.beginPath();
      c.moveTo(Math.cos(a) * r * 0.73, Math.sin(a) * r * 0.73);
      c.lineTo(Math.cos(a) * r * (i % 2 ? 0.84 : 0.98), Math.sin(a) * r * (i % 2 ? 0.84 : 0.98));
      c.stroke();
    }
    return;
  }
  if (motif === 'lotus') {
    rosette(c, r * 0.93, 8);
    c.save();
    c.rotate(Math.PI / 8);
    rosette(c, r * 0.72, 8);
    c.restore();
    circle(c, 0, 0, r * 0.17);
    return;
  }
  if (motif === 'laurel') {
    for (const side of [-1, 1]) {
      c.save();
      c.scale(side, 1);
      c.rotate(-Math.PI * 0.38);
      c.translate(-r * 0.72, r * 0.05);
      branch(c, r * 1.42, -r * 0.62);
      c.restore();
    }
    star(c, 0, -r * 0.62, r * 0.09);
    return;
  }
  if (motif === 'diamond') {
    for (const extent of [0.95, 0.7, 0.29]) {
      c.beginPath();
      c.moveTo(0, -r * extent);
      c.lineTo(r * extent, 0);
      c.lineTo(0, r * extent);
      c.lineTo(-r * extent, 0);
      c.closePath();
      c.stroke();
    }
    star(c, 0, 0, r * 0.15);
    return;
  }
  for (const extent of [0.97, 0.82, 0.6, 0.31]) circle(c, 0, 0, r * extent);
  for (let i = 0; i < 48; i++) {
    const a = (i * Math.PI) / 24;
    c.beginPath();
    c.moveTo(Math.cos(a) * r * 0.87, Math.sin(a) * r * 0.87);
    c.lineTo(Math.cos(a) * r * (i % 4 ? 0.92 : 0.97), Math.sin(a) * r * (i % 4 ? 0.92 : 0.97));
    c.stroke();
  }
}

function random(seed: number) {
  return () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
}

function celestial(c: Painter, w: number, h: number, scale: number, surface: SurfaceName) {
  const s = Math.min(w, h);
  c.save();
  c.translate(w / 2, h / 2);
  for (const radius of [0.17, 0.3, 0.43]) circle(c, 0, 0, (s * radius) / scale);
  for (const a of [-0.54, 0.7]) {
    c.beginPath();
    c.ellipse(0, 0, (s * 0.46) / scale, (s * 0.16) / scale, a, 0, Math.PI * 2);
    c.stroke();
  }
  for (let i = 0; i < 72; i++) {
    const a = (i * Math.PI) / 36;
    c.beginPath();
    c.moveTo((Math.cos(a) * s * 0.425) / scale, (Math.sin(a) * s * 0.425) / scale);
    const extent = i % 6 ? 0.418 : 0.403;
    c.lineTo((Math.cos(a) * s * extent) / scale, (Math.sin(a) * s * extent) / scale);
    c.stroke();
  }
  c.restore();
  const rng = random(34123);
  for (let i = 0; i < 48 * scale; i++) {
    const x = rng() * w;
    const y = rng() * h;
    star(c, x, y, s * (i % 7 ? 0.0018 : 0.005));
  }
  const points = [
    [0.23, 0.11],
    [0.38, 0.25],
    [0.57, 0.2],
    [0.79, 0.35],
    [0.84, 0.57],
    [0.67, 0.78],
    [0.36, 0.84],
    [0.15, 0.64],
  ];
  c.beginPath();
  points.forEach(([x, y], index) => (index ? c.lineTo(x * w, y * h) : c.moveTo(x * w, y * h)));
  c.stroke();
  for (const [x, y] of points) star(c, x * w, y * h, s * 0.006);
  if (surface === 'board') {
    c.save();
    c.globalAlpha *= 0.6;
    for (let y = 0; y < 5; y++)
      for (let x = 0; x < 5; x++) {
        c.save();
        c.translate(w / 2 + (((x - 2) * 1.09) / 6.09) * w, h / 2 + (((y - 2) * 1.09) / 6.09) * h);
        circle(c, 0, 0, s * 0.053);
        circle(c, 0, 0, s * 0.049);
        rosette(c, s * 0.028, (x + y) % 2 ? 8 : 12);
        c.restore();
      }
    c.restore();
  }
}

function botanical(c: Painter, w: number, h: number, scale: number) {
  const step = (Math.min(w, h) * 0.34) / scale;
  for (let y = -step; y < h + step; y += step)
    for (let x = -step; x < w + step; x += step) {
      c.save();
      c.translate(x + (Math.round(y / step) % 2 ? step / 2 : 0), y);
      c.rotate(-Math.PI / 4);
      branch(c, step * 0.97, -step * 0.13);
      c.restore();
    }
}

function artdeco(c: Painter, w: number, h: number, scale: number) {
  const step = (Math.min(w, h) * 0.24) / scale;
  for (let y = -step; y < h + step; y += step * 0.7)
    for (let x = -step; x < w + step; x += step) {
      c.save();
      c.translate(x + (Math.round(y / (step * 0.7)) % 2 ? step / 2 : 0), y);
      for (const r of [step * 0.32, step * 0.41, step * 0.48]) {
        c.beginPath();
        c.arc(0, 0, r, Math.PI, Math.PI * 2);
        c.stroke();
      }
      for (let i = 1; i < 12; i++) {
        const a = Math.PI + (i / 12) * Math.PI;
        c.beginPath();
        c.moveTo(Math.cos(a) * step * 0.32, Math.sin(a) * step * 0.32);
        c.lineTo(Math.cos(a) * step * 0.48, Math.sin(a) * step * 0.48);
        c.stroke();
      }
      c.beginPath();
      c.moveTo(-step * 0.48, 0);
      c.lineTo(0, step * 0.24);
      c.lineTo(step * 0.48, 0);
      c.stroke();
      c.restore();
    }
}

function gingham(c: Painter, w: number, h: number, scale: number) {
  const step = (Math.min(w, h) * 0.12) / scale;
  c.save();
  c.globalAlpha *= 0.6;
  for (let x = 0; x < w; x += step * 2) c.fillRect(x, 0, step, h);
  for (let y = 0; y < h; y += step * 2) c.fillRect(0, y, w, step);
  c.restore();
}

function guilloche(c: Painter, w: number, h: number, scale: number) {
  const s = Math.min(w, h);
  c.save();
  c.translate(w / 2, h / 2);
  for (let wave = 0; wave < 12; wave++) {
    c.beginPath();
    for (let i = 0; i <= 720; i++) {
      const a = (i / 720) * Math.PI * 2;
      const r =
        s * (0.3 + Math.sin(a * (9 + Math.round(scale * 2)) + wave * 0.18) * 0.11 + wave * 0.003);
      const x = Math.cos(a) * r;
      const y = Math.sin(a) * r;
      if (i) c.lineTo(x, y);
      else c.moveTo(x, y);
    }
    c.stroke();
  }
  circle(c, 0, 0, s * 0.19);
  circle(c, 0, 0, s * 0.185);
  c.restore();
}

function marble(c: Painter, w: number, h: number, scale: number) {
  const rng = random(91783);
  const opacity = c.globalAlpha;
  for (let line = -4; line < 12 * scale; line++) {
    const start = (line * h) / (9 * scale);
    const phase = rng() * Math.PI * 2;
    const path = new Path2D();
    for (let x = -30; x <= w + 30; x += 8) {
      const y =
        start +
        Math.sin((x / w) * 6 + phase) * h * 0.08 +
        Math.sin((x / w) * 21 + phase * 2) * h * 0.016 +
        x * 0.18;
      if (x === -30) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    c.globalAlpha = opacity * 0.065;
    c.lineWidth = h * 0.07;
    c.stroke(path);
    c.globalAlpha = opacity * 0.2;
    c.lineWidth = h * 0.01;
    c.stroke(path);
    c.globalAlpha = opacity * 0.8;
    c.lineWidth = Math.max(0.75, h * 0.0015);
    c.stroke(path);
  }
  c.globalAlpha = opacity;
}

export function layerPositions(layer: DesignLayer, width: number, height: number) {
  const size = Math.min(width, height) * layer.size;
  if (layer.placement === 'single')
    return [{ x: layer.x * width, y: layer.y * height, rotation: layer.rotation }];
  if (layer.placement === 'corners') {
    const x = size / 2 + width * (0.035 + (layer.x - 0.5) * 0.25);
    const y = size / 2 + height * (0.035 + (layer.y - 0.5) * 0.25);
    return [
      { x, y, rotation: layer.rotation },
      { x: width - x, y, rotation: layer.rotation + 90 },
      { x: width - x, y: height - y, rotation: layer.rotation + 180 },
      { x, y: height - y, rotation: layer.rotation + 270 },
    ];
  }
  // A bounded repeat count keeps even twelve small layers responsive on phones.
  const step = Math.max(size * 1.4, Math.min(width, height) * 0.14);
  const columns = Math.min(12, Math.ceil(width / step));
  const rows = Math.min(8, Math.ceil(height / step));
  return Array.from({ length: columns * rows }, (_, index) => ({
    x: (((index % columns) + layer.x) * width) / columns,
    y: ((Math.floor(index / columns) + layer.y) * height) / rows,
    rotation: layer.rotation,
  }));
}

function tintedImage(image: HTMLImageElement, color: string) {
  const canvas = document.createElement('canvas');
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  const c = canvas.getContext('2d')!;
  c.drawImage(image, 0, 0);
  c.globalCompositeOperation = 'source-in';
  c.fillStyle = color;
  c.fillRect(0, 0, canvas.width, canvas.height);
  return canvas;
}

function paintLayers(c: Painter, layers: DesignLayer[], w: number, h: number, lookup: ImageLookup) {
  for (const layer of layers) {
    const image = layer.kind === 'image' ? lookup(layer.imageId) : undefined;
    if (layer.kind === 'image' && !image) continue;
    const source = image && layer.tint ? tintedImage(image, layer.color) : image;
    const size = Math.min(w, h) * layer.size;
    for (const point of layerPositions(layer, w, h)) {
      c.save();
      c.translate(point.x, point.y);
      c.rotate((point.rotation * Math.PI) / 180);
      c.globalAlpha = layer.opacity;
      c.fillStyle = c.strokeStyle = layer.color;
      if (layer.kind === 'motif') paintMotif(c, layer.motif, size);
      else if (source && image) {
        const ratio = image.naturalWidth / image.naturalHeight;
        const width = ratio >= 1 ? size : size * ratio;
        const height = ratio >= 1 ? size / ratio : size;
        c.drawImage(source, -width / 2, -height / 2, width, height);
      }
      c.restore();
    }
  }
}

export function makeSurfaceTexture(
  surface: SurfaceName,
  signature: string,
  images: ImageLookup,
): CanvasTexture {
  const design = JSON.parse(signature) as Drawing;
  const width = surface === 'board' ? 1024 : 512;
  const height = surface.endsWith('Body') ? 256 : width;
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const c = canvas.getContext('2d')!;
  c.fillStyle = design.background;
  c.fillRect(0, 0, width, height);
  if (design.pattern !== 'none' || design.layers.length || design.border) {
    const glaze = c.createLinearGradient(0, 0, width, height);
    glaze.addColorStop(0, 'rgba(255,255,255,.045)');
    glaze.addColorStop(0.5, 'rgba(255,255,255,0)');
    glaze.addColorStop(1, 'rgba(0,0,0,.09)');
    c.fillStyle = glaze;
    c.fillRect(0, 0, width, height);
  }
  c.save();
  c.strokeStyle = c.fillStyle = design.ink;
  c.lineWidth = Math.max(0.85, Math.min(width, height) * 0.0018);
  c.globalAlpha = design.patternOpacity;
  if (design.pattern === 'celestial') celestial(c, width, height, design.patternScale, surface);
  if (design.pattern === 'botanical') botanical(c, width, height, design.patternScale);
  if (design.pattern === 'artdeco') artdeco(c, width, height, design.patternScale);
  if (design.pattern === 'guilloche') guilloche(c, width, height, design.patternScale);
  if (design.pattern === 'marble') marble(c, width, height, design.patternScale);
  if (design.pattern === 'gingham') gingham(c, width, height, design.patternScale);
  c.restore();
  if (design.border) {
    c.strokeStyle = c.fillStyle = design.ink;
    c.lineWidth = Math.max(1.25, width * 0.0019);
    if (surface.endsWith('Cap')) {
      circle(c, width / 2, height / 2, width * 0.435);
      circle(c, width / 2, height / 2, width * 0.41);
      for (let i = 0; i < 48; i++) {
        const a = (i * Math.PI) / 24;
        star(
          c,
          width / 2 + Math.cos(a) * width * 0.425,
          height / 2 + Math.sin(a) * height * 0.425,
          i % 4 ? 1 : 2.5,
        );
      }
    } else if (surface.endsWith('Body')) {
      for (const y of [height * 0.12, height * 0.16, height * 0.84, height * 0.88]) {
        c.beginPath();
        c.moveTo(0, y);
        c.lineTo(width, y);
        c.stroke();
      }
    } else {
      for (const inset of [0.029, 0.039]) {
        c.beginPath();
        c.roundRect(
          width * inset,
          height * inset,
          width * (1 - inset * 2),
          height * (1 - inset * 2),
          width * 0.054,
        );
        c.stroke();
      }
      for (let i = 0; i < 4; i++) {
        c.save();
        c.translate(width / 2, height / 2);
        c.rotate((i * Math.PI) / 2);
        c.translate(-width / 2, -height / 2);
        star(c, width / 2, width * 0.034, width * 0.007);
        c.restore();
      }
    }
  }
  paintLayers(c, design.layers, width, height, images);
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  texture.anisotropy = 4;
  return texture;
}
