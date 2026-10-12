export type PiecePalette = { body: string; cap: string; mark: string };
export type SkinPalette = {
  board: { body: string; rim: string; dot: string };
  dark: PiecePalette;
  light: PiecePalette;
  accent: string;
};
export type Skin = {
  id: string;
  name: string;
  builtin: boolean;
  palette: SkinPalette;
};
export type SkinCatalog = {
  schemaVersion: 1;
  revision: number;
  activeSkinId: string;
  skins: Skin[];
};

const classic: SkinPalette = {
  board: { body: '#ede8dc', rim: '#aca18b', dot: '#979992' },
  dark: { body: '#24272c', cap: '#24292f', mark: '#858992' },
  light: { body: '#eee4d2', cap: '#f5edde', mark: '#969286' },
  accent: '#3661ee',
};
export const BUILTIN_SKINS: readonly Skin[] = [
  { id: 'classic', name: 'Классика', builtin: true, palette: classic },
  {
    id: 'coffee-board',
    name: 'Кофейная доска',
    builtin: true,
    palette: {
      ...classic,
      board: { body: '#cbb394', rim: '#a58c6c', dot: '#826e55' },
    },
  },
  {
    id: 'coffee-pieces',
    name: 'Кофейные фишки',
    builtin: true,
    palette: { ...classic, light: { body: '#cbb394', cap: '#dcc4a3', mark: '#8f7b60' } },
  },
];
export const DEFAULT_SKIN_ID = 'coffee-board';
export function defaultCatalog(): SkinCatalog {
  return {
    schemaVersion: 1,
    revision: 0,
    activeSkinId: DEFAULT_SKIN_ID,
    skins: structuredClone([...BUILTIN_SKINS]),
  };
}
const record = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const color = (value: unknown): value is string =>
  typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value);
export function isPalette(value: unknown): value is SkinPalette {
  if (!record(value) || Object.keys(value).sort().join() !== 'accent,board,dark,light')
    return false;
  const part = (value: unknown, keys: string[]) =>
    record(value) &&
    Object.keys(value).sort().join() === keys.sort().join() &&
    keys.every((key) => color(value[key]));
  return (
    color(value.accent) &&
    part(value.board, ['body', 'rim', 'dot']) &&
    part(value.dark, ['body', 'cap', 'mark']) &&
    part(value.light, ['body', 'cap', 'mark'])
  );
}
export function isSkin(value: unknown): value is Skin {
  return (
    record(value) &&
    typeof value.id === 'string' &&
    (BUILTIN_SKINS.some((skin) => skin.id === value.id) ||
      /^custom-[a-f0-9]{32}$/.test(value.id)) &&
    typeof value.name === 'string' &&
    value.name.trim().length > 0 &&
    value.name.length <= 48 &&
    value.builtin === BUILTIN_SKINS.some((skin) => skin.id === value.id) &&
    isPalette(value.palette)
  );
}
export function isCatalog(value: unknown): value is SkinCatalog {
  if (!record(value) || !Array.isArray(value.skins)) return false;
  const skins = value.skins;
  return (
    value.schemaVersion === 1 &&
    Number.isSafeInteger(value.revision) &&
    Number(value.revision) >= 0 &&
    skins.length >= BUILTIN_SKINS.length &&
    skins.length <= BUILTIN_SKINS.length + 32 &&
    skins.every(isSkin) &&
    new Set(skins.map((skin) => skin.id)).size === skins.length &&
    BUILTIN_SKINS.every((builtin) => skins.some((skin) => skin.id === builtin.id)) &&
    skins.some((skin) => skin.id === value.activeSkinId)
  );
}

export function activeSkin(catalog: SkinCatalog): Skin {
  return catalog.skins.find((skin) => skin.id === catalog.activeSkinId) ?? BUILTIN_SKINS[1];
}
