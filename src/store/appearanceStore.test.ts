// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { defaultCatalog, DEFAULT_ROOM_COLOR, type SkinCatalog } from '../skins/catalog';
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
    skins: catalog.skins.map((skin) => {
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
