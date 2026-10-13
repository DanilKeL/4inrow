// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { defaultCatalog, DEFAULT_ROOM_COLOR, type SkinCatalog } from '../skins/catalog';
import { animeDesign, motifLayer } from '../skins/design';
import { initializeAppearance, useAppearance } from './appearanceStore';

class Stream extends EventTarget {
  static OPEN = 1;
  static instances: Stream[] = [];
  readyState = Stream.OPEN;
  close = vi.fn();
  constructor() {
    super();
    Stream.instances.push(this);
  }
  send(catalog: unknown) {
    this.dispatchEvent(new MessageEvent('skins', { data: JSON.stringify(catalog) }));
  }
}
let stop: (() => void) | undefined;
beforeEach(() => {
  Stream.instances = [];
  localStorage.clear();
  useAppearance.setState({ catalog: defaultCatalog() });
  vi.stubGlobal('EventSource', Stream);
  vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);
  vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(defaultCatalog()))),
  );
});
afterEach(() => {
  stop?.();
  stop = undefined;
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
const changed = (id: string, revision: number): SkinCatalog => ({
  ...defaultCatalog(),
  activeSkinId: id,
  revision,
});
it('preserves the selected style in old offline catalogs and caches the added room field', () => {
  const catalog = changed('coffee-pieces', 4);
  const legacy = {
    ...catalog,
    skins: catalog.skins
      .filter((skin) => !skin.artwork && !skin.design)
      .map((skin) => {
        const palette: Record<string, unknown> = { ...skin.palette };
        delete palette.room;
        return { ...skin, palette };
      }),
  };
  useAppearance.getState().setCatalog(legacy);
  expect(useAppearance.getState().catalog).toEqual(catalog);
  expect(JSON.parse(localStorage.getItem('four-skins-v1')!).skins[2].palette.room).toBe(
    DEFAULT_ROOM_COLOR,
  );
});
it('adds a newly shipped template without resetting an old offline selection', () => {
  const old = changed('coffee-pieces', 7);
  const legacy = { ...old, skins: old.skins.filter((skin) => skin.id !== 'nocturne') };
  useAppearance.getState().setCatalog(legacy);
  expect(useAppearance.getState().catalog.activeSkinId).toBe('coffee-pieces');
  expect(useAppearance.getState().catalog.revision).toBe(7);
  expect(
    useAppearance.getState().catalog.skins.find((skin) => skin.id === 'nocturne')?.artwork,
  ).toBe('nocturne');
});

it('caches a newly shipped Sakura template while preserving an old offline custom selection', () => {
  const old = changed('coffee-pieces', 14);
  old.skins = old.skins.filter((skin) => skin.id !== 'sakura-nocturne');
  const custom = {
    ...structuredClone(old.skins[0]),
    id: `custom-${'e'.repeat(32)}`,
    builtin: false,
    name: 'Сохранённая палитра',
  };
  custom.palette.board.body = '#b8a0d2';
  old.skins.push(custom);
  old.activeSkinId = custom.id;
  useAppearance.getState().setCatalog(old);
  const cached = JSON.parse(localStorage.getItem('four-skins-v1')!) as SkinCatalog;
  expect(cached).toEqual(useAppearance.getState().catalog);
  expect(cached.activeSkinId).toBe(custom.id);
  expect(cached.revision).toBe(14);
  expect(cached.skins.find((skin) => skin.id === custom.id)).toEqual(custom);
  expect(cached.skins.find((skin) => skin.id === 'sakura-nocturne')?.design).toEqual(animeDesign());
});

it('retains the edited Sakura copy when appearance requests fail offline', async () => {
  const catalog = changed('sakura-nocturne', 19);
  const template = catalog.skins.find((skin) => skin.id === 'sakura-nocturne')!;
  const copy = {
    ...structuredClone(template),
    id: `custom-${'f'.repeat(32)}`,
    name: 'Моя лунная сакура',
    builtin: false,
  };
  copy.design!.surfaces.board.ink = '#d8b7ff';
  copy.design!.surfaces.darkCap.layers.push(motifLayer('crest', '#d8b7ff', 'my-crest'));
  catalog.skins.push(copy);
  catalog.activeSkinId = copy.id;
  useAppearance.getState().setCatalog(catalog);
  vi.mocked(fetch).mockRejectedValue(new TypeError('Failed to fetch'));
  stop = initializeAppearance();
  await vi.waitFor(() => expect(Stream.instances).toHaveLength(1));
  expect(useAppearance.getState().catalog).toEqual(catalog);
  expect(JSON.parse(localStorage.getItem('four-skins-v1')!)).toEqual(catalog);
  expect(template.design).toEqual(animeDesign());
});

it('updates live, caches valid skins for offline play, and ignores malformed events', async () => {
  stop = initializeAppearance();
  await vi.waitFor(() => expect(Stream.instances).toHaveLength(1));
  const config = changed('classic', 5);
  Stream.instances[0].send(config);
  expect(useAppearance.getState().catalog).toEqual(config);
  expect(JSON.parse(localStorage.getItem('four-skins-v1')!)).toEqual(config);
  Stream.instances[0].send({ ...config, activeSkinId: 'unknown' });
  Stream.instances[0].send({ ...config, skins: [{ palette: { light: 'bad' } }] });
  expect(useAppearance.getState().catalog).toEqual(config);
});
it('closes background connections and accepts a restored server revision when returning', async () => {
  stop = initializeAppearance();
  await vi.waitFor(() => expect(Stream.instances).toHaveLength(1));
  Stream.instances[0].send(changed('classic', 9));
  vi.mocked(Object.getOwnPropertyDescriptor(document, 'hidden')!.get!).mockReturnValue(true);
  document.dispatchEvent(new Event('visibilitychange'));
  expect(Stream.instances[0].close).toHaveBeenCalledOnce();
  expect(useAppearance.getState().catalog.activeSkinId).toBe('classic');
  vi.mocked(Object.getOwnPropertyDescriptor(document, 'hidden')!.get!).mockReturnValue(false);
  document.dispatchEvent(new Event('visibilitychange'));
  await vi.waitFor(() => expect(Stream.instances).toHaveLength(2));
  Stream.instances[0].send(changed('coffee-pieces', 10));
  Stream.instances[1].send(changed('coffee-board', 1));
  expect(useAppearance.getState().catalog.activeSkinId).toBe('coffee-board');
  expect(useAppearance.getState().catalog.revision).toBe(1);
});
it('does not let an old delayed request replace the style after reconnecting', async () => {
  let release!: (value: Response) => void;
  vi.mocked(fetch).mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        release = resolve;
      }),
  );
  stop = initializeAppearance();
  document.dispatchEvent(new Event('visibilitychange'));
  await vi.waitFor(() => expect(Stream.instances).toHaveLength(1));
  Stream.instances[0].send(changed('coffee-pieces', 3));
  release(new Response(JSON.stringify(changed('classic', 20))));
  await vi.waitFor(() =>
    expect(useAppearance.getState().catalog.activeSkinId).toBe('coffee-pieces'),
  );
  expect(Stream.instances).toHaveLength(1);
});
