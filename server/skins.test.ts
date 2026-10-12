import { afterEach, expect, it } from 'vitest';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { SkinsStore } from './skins';
import { BUILTIN_SKINS, defaultCatalog, DEFAULT_ROOM_COLOR, isCatalog } from '../src/skins/catalog';
import { blankDesign, imageLayer, motifLayer, nocturneDesign } from '../src/skins/design';

const databases: DatabaseSync[] = [];
const directories: string[] = [];
function open(file = ':memory:') {
  const db = new DatabaseSync(file);
  databases.push(db);
  return new SkinsStore(db);
}
afterEach(() => {
  databases.splice(0).forEach((db) => db.close());
  for (const dir of directories.splice(0)) rmSync(dir, { recursive: true, force: true });
});
it('persists custom skins and the active selection in the backed-up SQLite database', () => {
  const dir = mkdtempSync(join(tmpdir(), 'four-skins-'));
  directories.push(dir);
  const file = join(dir, 'statistics.sqlite');
  const store = open(file);
  expect(store.get().activeSkinId).toBe('coffee-board');
  const palette = structuredClone(defaultCatalog().skins[0].palette);
  palette.board.body = '#bb9988';
  palette.room = '#9fabc1';
  const saved = store.save({ name: 'Тёплый камень', palette, expectedRevision: 0 });
  const activated = store.activate(saved.savedSkinId, saved.revision);
  databases.pop()!.close();
  const restored = open(file);
  expect(restored.get()).toEqual(activated);
  expect(isCatalog(restored.get())).toBe(true);
  const updated = restored.save(
    { name: 'Камень', palette, expectedRevision: activated.revision },
    saved.savedSkinId,
  );
  expect(updated.skins.find((skin) => skin.id === saved.savedSkinId)?.name).toBe('Камень');
});
it('keeps artwork when copying and restoring a template and rejects unknown renderers', () => {
  const store = open();
  const template = BUILTIN_SKINS.find((skin) => skin.id === 'nocturne')!;
  const copy = store.save({
    name: 'Мой атлас',
    palette: template.palette,
    artwork: template.artwork,
    expectedRevision: 0,
  });
  expect(copy.skins.find((skin) => skin.id === copy.savedSkinId)?.artwork).toBe('nocturne');
  expect(() =>
    store.save({ name: 'bad', palette: template.palette, artwork: 'unknown', expectedRevision: 1 }),
  ).toThrow();
  expect(store.get()).toEqual({ ...copy, savedSkinId: undefined });
});
it('retains pre-room database styles and accepts old clients without discarding their colors', () => {
  const store = open();
  const palette: Record<string, unknown> = structuredClone(defaultCatalog().skins[0].palette);
  delete palette.room;
  const saved = store.save({ name: 'Старый стиль', palette, expectedRevision: 0 });
  const skin = saved.skins.find((skin) => skin.id === saved.savedSkinId)!;
  expect(skin.palette.room).toBe(DEFAULT_ROOM_COLOR);
  const legacy = { ...skin, palette };
  databases
    .at(-1)!
    .prepare('UPDATE game_settings SET value=? WHERE key=?')
    .run(JSON.stringify({ revision: 3, activeSkinId: skin.id, custom: [legacy] }), 'skins.v1');
  const restored = store.get();
  expect(restored.activeSkinId).toBe(skin.id);
  expect(restored.revision).toBe(3);
  expect(restored.skins.at(-1)?.palette).toEqual({ ...palette, room: DEFAULT_ROOM_COLOR });
  expect(isCatalog(restored)).toBe(true);
  const before = store.get();
  expect(() =>
    store.save({ name: 'bad', palette: { ...palette, room: 'red' }, expectedRevision: 3 }),
  ).toThrow();
  expect(store.get()).toEqual(before);
});
it('rejects stale writes, invalid colors and changes to built-ins without mutating the catalog', () => {
  const store = open();
  const palette = structuredClone(defaultCatalog().skins[0].palette);
  store.activate('classic', 0);
  const before = store.get();
  expect(() => store.activate('coffee-board', 0)).toThrow('другом окне');
  expect(() => store.activate('missing', 1)).toThrow('не найден');
  expect(() =>
    store.save({ name: 'bad', palette: { ...palette, accent: 'url(evil)' }, expectedRevision: 1 }),
  ).toThrow();
  expect(() => store.save({ name: 'bad', palette, expectedRevision: 1 }, 'classic')).toThrow();
  expect(() => store.remove('classic', 1)).toThrow();
  expect(store.get()).toEqual(before);
});
it('protects the active skin, supports deleting inactive custom styles, and keeps names unique', () => {
  const store = open();
  const palette = defaultCatalog().skins[0].palette;
  const saved = store.save({ name: 'Мой стиль', palette, expectedRevision: 0 });
  expect(() => store.save({ name: 'мой стиль', palette, expectedRevision: 1 })).toThrow('название');
  store.activate(saved.savedSkinId, 1);
  expect(() => store.remove(saved.savedSkinId, 2)).toThrow('другой стиль');
  store.activate('coffee-board', 2);
  const removed = store.remove(saved.savedSkinId, 3);
  expect(removed.skins).toHaveLength(BUILTIN_SKINS.length);
  expect(removed.activeSkinId).toBe('coffee-board');
});
it('persists the full layered composition, rejects malformed layers atomically, and permits clearing it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'four-skin-design-'));
  directories.push(dir);
  const file = join(dir, 'statistics.sqlite');
  const store = open(file);
  const palette = BUILTIN_SKINS.find((skin) => skin.id === 'nocturne')!.palette;
  const design = nocturneDesign();
  const saved = store.save({ name: 'Моя композиция', palette, design, expectedRevision: 0 });
  const active = store.activate(saved.savedSkinId, saved.revision);
  databases.pop()!.close();
  const restored = open(file);
  expect(restored.get()).toEqual(active);
  expect(isCatalog(restored.get())).toBe(true);
  const invalid = structuredClone(design);
  invalid.surfaces.board.layers.push({ ...motifLayer('star'), x: 50 });
  expect(() =>
    restored.save(
      { name: 'Bad', palette, design: invalid, expectedRevision: active.revision },
      saved.savedSkinId,
    ),
  ).toThrow('Некорректный стиль');
  expect(restored.get()).toEqual(active);
  const cleared = restored.save(
    { name: 'Без узоров', palette, expectedRevision: active.revision },
    saved.savedSkinId,
  );
  expect(cleared.skins.find((skin) => skin.id === saved.savedSkinId)?.design).toBeUndefined();
});
it('requires uploaded assets before saving and deduplicates references across surfaces', () => {
  const db = new DatabaseSync(':memory:');
  databases.push(db);
  const asset = 'b'.repeat(64);
  const store = new SkinsStore(db, (id) => id === asset);
  const design = blankDesign();
  design.surfaces.board.layers = [imageLayer(asset)];
  const palette = defaultCatalog().skins[0].palette;
  const saved = store.save({ name: 'Картинка', palette, design, expectedRevision: 0 });
  expect(saved.skins.at(-1)?.design).toEqual(design);
  Object.assign(design.surfaces.board.layers[0], { imageId: 'c'.repeat(64) });
  expect(() =>
    store.save({ name: 'Нет картинки', palette, design, expectedRevision: saved.revision }),
  ).toThrow('загрузите');
  expect(store.get().revision).toBe(saved.revision);
});
