import { ANIME_HEROINE_IMAGE_ID } from './builtinAssets.ts';

export const SURFACES = ['board', 'darkCap', 'darkBody', 'lightCap', 'lightBody'] as const;
export type SurfaceName = (typeof SURFACES)[number];
export const PATTERNS = [
  'none',
  'celestial',
  'botanical',
  'artdeco',
  'guilloche',
  'marble',
  'gingham',
  'sakura-waves',
] as const;
export type Pattern = (typeof PATTERNS)[number];
export const MOTIFS = [
  'moon',
  'sun',
  'star',
  'lotus',
  'laurel',
  'diamond',
  'rings',
  'heart',
  'bow',
  'blossom',
  'sakura',
  'kitsune',
  'crest',
] as const;
export type Motif = (typeof MOTIFS)[number];
export type Placement = 'single' | 'corners' | 'grid';
type LayerBase = {
  id: string;
  x: number;
  y: number;
  size: number;
  rotation: number;
  opacity: number;
  color: string;
  tint: boolean;
  placement: Placement;
};
export type DesignLayer = LayerBase &
  ({ kind: 'motif'; motif: Motif } | { kind: 'image'; imageId: string });
export type SurfaceDesign = {
  pattern: Pattern;
  ink: string;
  patternScale: number;
  patternOpacity: number;
  border: boolean;
  roughness: number;
  metalness: number;
  layers: DesignLayer[];
};
export type SkinDesign = { version: 1; surfaces: Record<SurfaceName, SurfaceDesign> };
export const MAX_DESIGN_IMAGES = 16;

const record = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const color = (value: unknown): value is string =>
  typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value);
const range = (value: unknown, min: number, max: number) =>
  typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
const keys = (value: Record<string, unknown>, expected: string[]) =>
  Object.keys(value).sort().join() === [...expected].sort().join();

export function isDesignLayer(value: unknown): value is DesignLayer {
  if (!record(value)) return false;
  const base = [
    'id',
    'kind',
    'x',
    'y',
    'size',
    'rotation',
    'opacity',
    'color',
    'tint',
    'placement',
  ];
  return (
    typeof value.id === 'string' &&
    /^[a-zA-Z0-9_-]{1,48}$/.test(value.id) &&
    range(value.x, 0, 1) &&
    range(value.y, 0, 1) &&
    range(value.size, 0.05, 1) &&
    range(value.rotation, -180, 180) &&
    range(value.opacity, 0, 1) &&
    color(value.color) &&
    typeof value.tint === 'boolean' &&
    ['single', 'corners', 'grid'].includes(String(value.placement)) &&
    ((value.kind === 'motif' &&
      MOTIFS.includes(value.motif as Motif) &&
      keys(value, [...base, 'motif'])) ||
      (value.kind === 'image' &&
        typeof value.imageId === 'string' &&
        /^[a-f0-9]{64}$/.test(value.imageId) &&
        keys(value, [...base, 'imageId'])))
  );
}
export function isSkinDesign(value: unknown): value is SkinDesign {
  if (
    !record(value) ||
    !keys(value, ['version', 'surfaces']) ||
    value.version !== 1 ||
    !record(value.surfaces) ||
    !keys(value.surfaces, [...SURFACES])
  )
    return false;
  const surfaces = value.surfaces;
  const valid = SURFACES.every((surface) => {
    const part = surfaces[surface];
    return (
      record(part) &&
      keys(part, [
        'pattern',
        'ink',
        'patternScale',
        'patternOpacity',
        'border',
        'roughness',
        'metalness',
        'layers',
      ]) &&
      PATTERNS.includes(part.pattern as Pattern) &&
      color(part.ink) &&
      range(part.patternScale, 0.5, 3) &&
      range(part.patternOpacity, 0, 1) &&
      typeof part.border === 'boolean' &&
      range(part.roughness, 0, 1) &&
      range(part.metalness, 0, 1) &&
      Array.isArray(part.layers) &&
      part.layers.length <= 12 &&
      part.layers.every(isDesignLayer) &&
      new Set(part.layers.map((layer) => layer.id)).size === part.layers.length
    );
  });
  return valid && designImageIds(value as SkinDesign).length <= MAX_DESIGN_IMAGES;
}
export function blankDesign(ink = '#c8a970'): SkinDesign {
  const surfaces = {} as SkinDesign['surfaces'];
  for (const surface of SURFACES)
    surfaces[surface] = {
      pattern: 'none',
      ink,
      patternScale: 1,
      patternOpacity: 0.65,
      border: false,
      roughness: surface === 'board' ? 0.42 : 0.5,
      metalness: 0,
      layers: [],
    };
  return { version: 1, surfaces };
}
export function motifLayer(
  motif: Motif,
  color = '#c8a970',
  id = `motif-${motif}`,
): Extract<DesignLayer, { kind: 'motif' }> {
  return {
    id,
    kind: 'motif',
    motif,
    x: 0.5,
    y: 0.5,
    size: 0.56,
    rotation: 0,
    opacity: 1,
    color,
    tint: false,
    placement: 'single',
  };
}
export function imageLayer(
  imageId: string,
  color = '#c8a970',
  id = `image-${imageId.slice(0, 12)}`,
): Extract<DesignLayer, { kind: 'image' }> {
  return {
    id,
    kind: 'image',
    imageId,
    x: 0.5,
    y: 0.5,
    size: 0.56,
    rotation: 0,
    opacity: 1,
    color,
    tint: false,
    placement: 'single',
  };
}
export function nocturneDesign(): SkinDesign {
  const design = blankDesign('#d8bc7f');
  const { board, darkCap, lightCap, darkBody, lightBody } = design.surfaces;
  Object.assign(board, {
    pattern: 'celestial',
    patternOpacity: 0.8,
    border: true,
    roughness: 0.3,
    metalness: 0.55,
  });
  board.layers = [{ ...motifLayer('laurel', '#d8bc7f'), size: 0.2, placement: 'corners' }];
  Object.assign(darkCap, {
    pattern: 'celestial',
    patternOpacity: 0.5,
    border: true,
    roughness: 0.36,
    metalness: 0.2,
  });
  darkCap.layers = [motifLayer('moon', '#dfc688')];
  Object.assign(lightCap, {
    ink: '#947244',
    pattern: 'guilloche',
    patternOpacity: 0.3,
    border: true,
    roughness: 0.42,
    metalness: 0.1,
  });
  lightCap.layers = [motifLayer('sun', '#947244')];
  Object.assign(darkBody, {
    pattern: 'botanical',
    patternOpacity: 0.5,
    border: true,
    roughness: 0.38,
    metalness: 0.15,
  });
  Object.assign(lightBody, {
    pattern: 'botanical',
    ink: '#947244',
    patternOpacity: 0.4,
    border: true,
    roughness: 0.44,
    metalness: 0.08,
  });
  return design;
}
/** A porcelain-and-ribbon composition; every ornament remains editable. */
export function pickmiDesign(): SkinDesign {
  const design = blankDesign('#cf91a1');
  const { board, darkCap, lightCap, darkBody, lightBody } = design.surfaces;
  Object.assign(board, {
    pattern: 'gingham',
    patternScale: 1.1,
    patternOpacity: 0.18,
    border: true,
    roughness: 0.34,
    metalness: 0.04,
  });
  board.layers = [
    {
      ...motifLayer('bow', '#b96583', 'corner-ribbons'),
      size: 0.11,
      placement: 'corners',
      opacity: 0.9,
    },
    { ...motifLayer('heart', '#bd718c', 'little-heart'), x: 0.5, y: 0.927, size: 0.073 },
    {
      ...motifLayer('blossom', '#fffbf3', 'porcelain-flowers'),
      size: 0.05,
      placement: 'grid',
      opacity: 0.72,
    },
  ];
  Object.assign(darkCap, { ink: '#ffe8ec', border: true, roughness: 0.28, metalness: 0.02 });
  darkCap.layers = [
    { ...motifLayer('heart', '#ffecdf', 'cream-heart'), size: 0.5 },
    {
      ...motifLayer('star', '#ffe7e9', 'tiny-sparkle'),
      x: 0.74,
      y: 0.26,
      size: 0.11,
      opacity: 0.8,
    },
  ];
  Object.assign(lightCap, { ink: '#bf8599', border: true, roughness: 0.3, metalness: 0.02 });
  lightCap.layers = [
    { ...motifLayer('bow', '#b65074', 'berry-bow'), size: 0.58 },
    { ...motifLayer('blossom', '#d58aa2', 'tiny-flower'), x: 0.27, y: 0.26, size: 0.13 },
  ];
  Object.assign(darkBody, {
    pattern: 'gingham',
    ink: '#fff0e8',
    patternOpacity: 0.12,
    patternScale: 1.5,
    border: true,
    roughness: 0.32,
    metalness: 0.03,
  });
  darkBody.layers = [
    {
      ...motifLayer('heart', '#ffdfdf', 'ribbon-hearts'),
      size: 0.13,
      placement: 'grid',
      opacity: 0.7,
    },
  ];
  Object.assign(lightBody, {
    pattern: 'gingham',
    ink: '#d694aa',
    patternOpacity: 0.24,
    patternScale: 1.5,
    border: true,
    roughness: 0.32,
    metalness: 0.03,
  });
  lightBody.layers = [
    {
      ...motifLayer('blossom', '#b97b96', 'ribbon-flowers'),
      size: 0.14,
      placement: 'grid',
      opacity: 0.75,
    },
  ];
  return design;
}
/** Moonlit Sakura: original anime artwork paired with editable lacquer and foil ornaments. */
export function animeDesign(): SkinDesign {
  const design = blankDesign('#abcce2');
  const { board, darkCap, lightCap, darkBody, lightBody } = design.surfaces;
  Object.assign(board, {
    pattern: 'sakura-waves',
    patternScale: 0.95,
    patternOpacity: 0.6,
    border: true,
    roughness: 0.31,
    metalness: 0.22,
  });
  board.layers = [
    {
      ...motifLayer('crest', '#b3d7ef', 'silver-seals'),
      size: 0.13,
      opacity: 0.85,
      placement: 'corners',
    },
    { ...motifLayer('kitsune', '#ee9fab', 'fox-seal'), x: 0.5, y: 0.935, size: 0.07 },
  ];
  Object.assign(darkCap, { ink: '#c6e4f4', border: true, roughness: 0.3, metalness: 0.1 });
  darkCap.layers = [
    { ...imageLayer(ANIME_HEROINE_IMAGE_ID, '#ffffff', 'moonlit-heroine'), size: 0.86, y: 0.48 },
  ];
  Object.assign(lightCap, { ink: '#93718e', border: true, roughness: 0.34, metalness: 0.08 });
  lightCap.layers = [
    { ...motifLayer('kitsune', '#34436b', 'silver-fox'), size: 0.66 },
    { ...motifLayer('sakura', '#d3779d', 'sakura-mark'), x: 0.74, y: 0.25, size: 0.18 },
  ];
  Object.assign(darkBody, {
    pattern: 'sakura-waves',
    ink: '#a7cbe7',
    patternScale: 1.4,
    patternOpacity: 0.24,
    border: true,
    roughness: 0.34,
    metalness: 0.12,
  });
  darkBody.layers = [
    {
      ...motifLayer('sakura', '#ec9ab3', 'falling-sakura'),
      size: 0.2,
      placement: 'grid',
      opacity: 0.68,
    },
  ];
  Object.assign(lightBody, {
    pattern: 'sakura-waves',
    ink: '#7d89b4',
    patternScale: 1.6,
    patternOpacity: 0.17,
    border: true,
    roughness: 0.35,
    metalness: 0.07,
  });
  lightBody.layers = [
    {
      ...motifLayer('crest', '#4b5b87', 'moon-ribbon'),
      size: 0.15,
      placement: 'grid',
      opacity: 0.6,
    },
  ];
  return design;
}
export function designImageIds(design?: SkinDesign): string[] {
  return [
    ...new Set(
      design
        ? SURFACES.flatMap((surface) =>
            design.surfaces[surface].layers.flatMap((layer) =>
              layer.kind === 'image' ? [layer.imageId] : [],
            ),
          )
        : [],
    ),
  ];
}
