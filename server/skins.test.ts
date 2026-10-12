import { afterEach, expect, it } from 'vitest';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { SkinsStore } from './skins';
import { defaultCatalog, isCatalog } from '../src/skins/catalog';

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
  expect(removed.skins).toHaveLength(3);
  expect(removed.activeSkinId).toBe('coffee-board');
});
