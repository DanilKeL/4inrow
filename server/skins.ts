import type { DatabaseSync } from 'node:sqlite';
import { randomBytes } from 'node:crypto';
import { AuthError } from './auth.ts';
import {
  BUILTIN_SKINS,
  DEFAULT_SKIN_ID,
  isPalette,
  isSkin,
  type Skin,
  type SkinCatalog,
} from '../src/skins/catalog.ts';

type SavedCatalog = { revision: number; activeSkinId: string; custom: Skin[] };
export class SkinsStore {
  constructor(private db: DatabaseSync) {
    db.exec('CREATE TABLE IF NOT EXISTS game_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }
  private read(): SavedCatalog {
    const row = this.db.prepare('SELECT value FROM game_settings WHERE key=?').get('skins.v1');
    if (!row) return { revision: 0, activeSkinId: DEFAULT_SKIN_ID, custom: [] };
    return JSON.parse(String(row.value)) as SavedCatalog;
  }
  get(): SkinCatalog {
    const saved = this.read();
    return {
      schemaVersion: 1,
      revision: saved.revision,
      activeSkinId: saved.activeSkinId,
      skins: structuredClone([...BUILTIN_SKINS, ...saved.custom]),
    };
  }
  private change(expected: unknown, update: (saved: SavedCatalog) => void): SkinCatalog {
    if (!Number.isSafeInteger(expected) || Number(expected) < 0)
      throw new AuthError(400, 'Укажите версию каталога стилей.');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const saved = this.read();
      if (saved.revision !== expected)
        throw new AuthError(409, 'Стили изменены в другом окне. Обновите каталог.');
      update(saved);
      saved.revision++;
      this.db
        .prepare(
          'INSERT INTO game_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        )
        .run('skins.v1', JSON.stringify(saved));
      this.db.exec('COMMIT');
      return this.get();
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }
  activate(id: unknown, expected: unknown) {
    return this.change(expected, (saved) => {
      if (![...BUILTIN_SKINS, ...saved.custom].some((skin) => skin.id === id))
        throw new AuthError(400, 'Стиль не найден.');
      saved.activeSkinId = String(id);
    });
  }
  save(data: Record<string, unknown>, id?: string) {
    if (BUILTIN_SKINS.some((builtin) => builtin.id === id))
      throw new AuthError(403, 'Готовый стиль можно изменить только в собственной копии.');
    if (
      typeof data.name !== 'string' ||
      !data.name.trim() ||
      data.name.trim().length > 48 ||
      !isPalette(data.palette)
    )
      throw new AuthError(400, 'Проверьте название и цвета стиля.');
    const skin: Skin = {
      id: id ?? `custom-${randomBytes(16).toString('hex')}`,
      name: data.name.trim(),
      builtin: false,
      palette: structuredClone(data.palette),
    };
    if (!isSkin(skin)) throw new AuthError(400, 'Некорректный стиль.');
    const catalog = this.change(data.expectedRevision, (saved) => {
      if (id && !saved.custom.some((current) => current.id === id))
        throw new AuthError(404, 'Стиль не найден.');
      if (!id && saved.custom.length >= 32)
        throw new AuthError(400, 'Можно сохранить до 32 собственных стилей.');
      if (
        [...BUILTIN_SKINS, ...saved.custom].some(
          (current) =>
            current.id !== id &&
            current.name.toLocaleLowerCase('ru') === skin.name.toLocaleLowerCase('ru'),
        )
      )
        throw new AuthError(409, 'Такое название стиля уже есть.');
      if (id) saved.custom = saved.custom.map((current) => (current.id === id ? skin : current));
      else saved.custom.push(skin);
    });
    return { ...catalog, savedSkinId: skin.id };
  }
  remove(id: string, expected: unknown) {
    return this.change(expected, (saved) => {
      if (BUILTIN_SKINS.some((skin) => skin.id === id))
        throw new AuthError(403, 'Готовые стили удалять нельзя.');
      if (saved.activeSkinId === id) throw new AuthError(409, 'Сначала включите другой стиль.');
      if (!saved.custom.some((skin) => skin.id === id))
        throw new AuthError(404, 'Стиль не найден.');
      saved.custom = saved.custom.filter((skin) => skin.id !== id);
    });
  }
}
