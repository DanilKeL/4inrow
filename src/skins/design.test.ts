import { expect, it } from 'vitest';
import {
  animeDesign,
  blankDesign,
  designImageIds,
  MAX_DESIGN_IMAGES,
  isSkinDesign,
  imageLayer,
  motifLayer,
  nocturneDesign,
  pickmiDesign,
  SURFACES,
} from './design';
import { defaultCatalog, isCatalog, normalizeCatalog } from './catalog';

it('accepts blank and fully editable Nocturne compositions without changing legacy skins', () => {
  expect(isSkinDesign(blankDesign())).toBe(true);
  const design = nocturneDesign();
  expect(isSkinDesign(design)).toBe(true);
  expect(design.surfaces.darkCap.layers[0]).toMatchObject({ kind: 'motif', motif: 'moon' });
  expect(design.surfaces.lightCap.layers[0]).toMatchObject({ kind: 'motif', motif: 'sun' });
  const catalog = defaultCatalog();
  const legacy = structuredClone(catalog);
  catalog.skins.push({
    ...catalog.skins[0],
    id: `custom-${'a'.repeat(32)}`,
    builtin: false,
    name: 'Композиция',
    design,
  });
  expect(isCatalog(catalog)).toBe(true);
  expect(normalizeCatalog(catalog)).toEqual(catalog);
  expect(normalizeCatalog(legacy)).toEqual(legacy);
});
it('keeps surface defaults independent and enforces exactly five surfaces', () => {
  const design = blankDesign();
  design.surfaces.darkCap.layers.push(motifLayer('moon'));
  expect(design.surfaces.lightCap.layers).toEqual([]);
  const missing = structuredClone(design) as unknown as { surfaces: Record<string, unknown> };
  delete missing.surfaces.lightBody;
  expect(isSkinDesign(missing)).toBe(false);
  const extra = { ...design, surfaces: { ...design.surfaces, room: design.surfaces.board } };
  expect(isSkinDesign(extra)).toBe(false);
});
it('rejects invalid pattern, motif, non-finite parameters, injected URLs and duplicate or excessive layers', () => {
  const valid = nocturneDesign();
  const changes: [string, unknown][] = [
    ['pattern', 'external'],
    ['ink', 'url(https://example.com)'],
    ['metalness', NaN],
    ['roughness', Infinity],
    ['patternScale', 4],
    ['patternOpacity', -0.1],
    ['border', 'yes'],
  ];
  for (const [field, value] of changes) {
    const bad = structuredClone(valid);
    Object.assign(bad.surfaces.board, { [field]: value });
    expect(isSkinDesign(bad), field).toBe(false);
  }
  const layerChanges: [string, unknown][] = [
    ['x', 1.1],
    ['y', -1],
    ['size', 0],
    ['rotation', 181],
    ['opacity', Infinity],
    ['motif', 'external'],
    ['tint', 1],
    ['placement', 'custom'],
    ['id', '../evil'],
    ['url', 'https://example.com/image.png'],
  ];
  for (const [field, value] of layerChanges) {
    const bad = structuredClone(valid);
    Object.assign(bad.surfaces.darkCap.layers[0], { [field]: value });
    expect(isSkinDesign(bad), field).toBe(false);
  }
  const duplicate = blankDesign();
  duplicate.surfaces.board.layers = [motifLayer('sun'), motifLayer('sun')];
  expect(isSkinDesign(duplicate)).toBe(false);
  duplicate.surfaces.board.layers = Array.from({ length: 13 }, (_, i) =>
    motifLayer('star', '#123456', `star-${i}`),
  );
  expect(isSkinDesign(duplicate)).toBe(false);
  duplicate.surfaces.board.layers.pop();
  expect(isSkinDesign(duplicate)).toBe(true);
});
it('extracts unique server image references and rejects data URLs as layer sources', () => {
  const design = blankDesign();
  const id = 'a'.repeat(64);
  for (const surface of SURFACES) design.surfaces[surface].layers = [imageLayer(id)];
  expect(isSkinDesign(design)).toBe(true);
  expect(designImageIds(design)).toEqual([id]);
  expect(designImageIds()).toEqual([]);
  const bad = structuredClone(design);
  Object.assign(bad.surfaces.board.layers[0], { imageId: 'data:image/svg+xml;base64,AAAA' });
  expect(isSkinDesign(bad)).toBe(false);
});
it('bounds decoded image memory while allowing repeated references across all surfaces', () => {
  const design = blankDesign();
  for (let i = 0; i < MAX_DESIGN_IMAGES + 1; i++) {
    const surface = SURFACES[Math.floor(i / 12)];
    design.surfaces[surface].layers.push(
      imageLayer(i.toString(16).padStart(64, '0'), '#123456', `image-${i}`),
    );
  }
  expect(isSkinDesign(design)).toBe(false);
  design.surfaces.darkCap.layers.pop();
  expect(isSkinDesign(design)).toBe(true);
});

it('upgrades old offline catalogs with Pickmi while keeping the selected skin and its saved colors', () => {
  const before = defaultCatalog();
  before.skins = before.skins.filter((skin) => skin.id !== 'pickmi');
  before.skins[0].palette.board.body = '#eedddd';
  const restored = normalizeCatalog(before)!;
  expect(restored.activeSkinId).toBe(before.activeSkinId);
  expect(restored.skins[0].palette.board.body).toBe('#eedddd');
  expect(restored.skins.find((skin) => skin.id === 'pickmi')?.design).toEqual(pickmiDesign());
  expect(isSkinDesign(pickmiDesign())).toBe(true);
  expect(designImageIds(pickmiDesign())).toEqual([]);
});

it('accepts the Sakura composition and gives each editable copy independent surfaces and layers', () => {
  const original = animeDesign();
  const copy = animeDesign();
  expect(isSkinDesign(original)).toBe(true);
  expect(copy).toEqual(original);
  expect(original.surfaces.board.pattern).toBe('sakura-waves');
  const motifs = SURFACES.flatMap((surface) =>
    original.surfaces[surface].layers.flatMap((layer) =>
      layer.kind === 'motif' ? [layer.motif] : [],
    ),
  );
  expect(motifs).toEqual(expect.arrayContaining(['sakura', 'kitsune', 'crest']));
  for (const surface of SURFACES) {
    expect(copy.surfaces[surface]).not.toBe(original.surfaces[surface]);
    expect(copy.surfaces[surface].layers).not.toBe(original.surfaces[surface].layers);
  }
  copy.surfaces.board.ink = '#abcdef';
  copy.surfaces.darkCap.layers.push(motifLayer('sakura', '#abcdef', 'my-sakura'));
  expect(original).toEqual(animeDesign());
  expect(isSkinDesign(copy)).toBe(true);
});

it('adds Sakura to an old catalog without resetting a selected custom composition or its colors', () => {
  const before = defaultCatalog();
  before.skins = before.skins.filter((skin) => skin.id !== 'sakura-nocturne');
  const custom = {
    ...structuredClone(before.skins[0]),
    id: `custom-${'d'.repeat(32)}`,
    builtin: false,
    name: 'Мой сохранённый стиль',
    design: pickmiDesign(),
  };
  custom.palette.room = '#e8dcf0';
  custom.design.surfaces.board.ink = '#a778be';
  before.skins.push(custom);
  before.activeSkinId = custom.id;
  before.revision = 23;
  const saved = structuredClone(before);
  const restored = normalizeCatalog(before)!;
  expect(restored.activeSkinId).toBe(custom.id);
  expect(restored.revision).toBe(23);
  expect(restored.skins.find((skin) => skin.id === custom.id)).toEqual(custom);
  expect(restored.skins.find((skin) => skin.id === 'sakura-nocturne')).toMatchObject({
    name: 'Лунная сакура',
    builtin: true,
    design: animeDesign(),
  });
  expect(isCatalog(restored)).toBe(true);
  expect(normalizeCatalog(restored)).toEqual(restored);
  expect(before).toEqual(saved);
});
