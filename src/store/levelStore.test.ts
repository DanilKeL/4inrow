// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { useLevelProgress } from './levelStore';
import { useAccount } from './accountStore';

beforeEach(() => {
  localStorage.clear();
  useAccount.setState({ username: null });
  useLevelProgress.setState({
    best: {},
    guestBest: {},
    accounts: {},
    legacyPending: false,
    owner: null,
    dirty: false,
    error: '',
  });
});
afterEach(() => {
  useAccount.setState({ username: null });
  vi.unstubAllGlobals();
});

it('imports old local records once, merges server best, and isolates accounts', async () => {
  localStorage.setItem(
    'four-cubed-levels-v1',
    JSON.stringify({ version: 1, state: { best: { 1: 5, 2: 3 } } }),
  );
  await useLevelProgress.persist.rehydrate();
  const fetcher = vi.fn(async (_url: string, options: RequestInit) => {
    const body = JSON.parse(options.body as string);
    return {
      ok: true,
      json: async () => ({
        username: body.owner,
        best: body.owner === 'Alice' ? { ...body.best, 1: 2, 3: 4 } : body.best,
      }),
    };
  });
  vi.stubGlobal('fetch', fetcher);
  useAccount.setState({ username: 'Alice' });
  await useLevelProgress.getState().refresh();
  expect(useLevelProgress.getState().best).toEqual({ 1: 2, 2: 3, 3: 4 });
  useAccount.setState({ username: 'Bob' });
  await useLevelProgress.getState().refresh();
  expect(useLevelProgress.getState().best).toEqual({});
  useAccount.setState({ username: 'Alice' });
  await useLevelProgress.getState().refresh();
  expect(useLevelProgress.getState().best[2]).toBe(3);
});

it('retains failed uploads across reload and retries without worsening a record', async () => {
  vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline')));
  useAccount.setState({ username: 'Alice' });
  await useLevelProgress.getState().refresh();
  useLevelProgress.getState().record(1, 5);
  await useLevelProgress.getState().refresh();
  await useLevelProgress.persist.rehydrate();
  expect(useLevelProgress.getState().best[1]).toBe(5);
  const upload = vi.fn(async (_url: string, options: RequestInit) => {
    const body = JSON.parse(options.body as string);
    return { ok: true, json: async () => ({ username: body.owner, best: body.best }) };
  });
  vi.stubGlobal('fetch', upload);
  await useLevelProgress.getState().refresh();
  expect(useLevelProgress.getState().dirty).toBe(false);
  expect(JSON.parse(upload.mock.calls[0][1].body as string).best).toEqual({ 1: 5 });
});

it('ignores a response belonging to a previous account', async () => {
  let resolve!: (response: object) => void;
  vi.stubGlobal(
    'fetch',
    vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise((done) => {
            resolve = done;
          }),
      )
      .mockResolvedValue({ ok: true, json: async () => ({ username: 'Bob', best: { 2: 4 } }) }),
  );
  useAccount.setState({ username: 'Alice' });
  const oldRequest = useLevelProgress.getState().refresh();
  useAccount.setState({ username: 'Bob' });
  await useLevelProgress.getState().refresh();
  resolve({ ok: true, json: async () => ({ username: 'Alice', best: { 1: 2 } }) });
  await oldRequest;
  expect(useLevelProgress.getState().best).toEqual({ 2: 4 });
});
it('retains only the lowest winning move count, separately for each level, across reloads', async () => {
  const { record } = useLevelProgress.getState();
  record(1, 5);
  record(1, 7);
  record(2, 3);
  record(1, 4);
  expect(useLevelProgress.getState().best).toEqual({ 1: 4, 2: 3 });
  await useLevelProgress.persist.rehydrate();
  expect(useLevelProgress.getState().best).toEqual({ 1: 4, 2: 3 });
});
it('rejects invalid data and does not break a win when storage is unavailable', () => {
  const blocked = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
    throw new Error('Storage full');
  });
  try {
    const { record } = useLevelProgress.getState();
    record(0, 2);
    record(41, 2);
    record(2, NaN);
    record(2, 0);
    record(2, -1);
    expect(useLevelProgress.getState().best).toEqual({});
    expect(() => record(2, 3)).not.toThrow();
    expect(useLevelProgress.getState().best[2]).toBe(3);
  } finally {
    blocked.mockRestore();
  }
});
