// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { replay } from '../game/core';
import { useMatchHistory } from './matchHistory';
import { useAccount } from './accountStore';

const game = replay(
  [
    [0, 0],
    [0, 4],
    [1, 0],
    [1, 4],
    [2, 0],
    [2, 4],
    [3, 0],
  ].map(([x, y]) => ({ x, y })),
);
const entry = {
  id: 'local-test',
  names: ['Alice', 'Bob'] as [string, string],
  mode: 'local' as const,
  elapsed: 45,
  game,
  owner: 'Alice',
};
const response = () => ({
  ok: true,
  json: async () => ({
    username: 'Alice',
    matches: [],
    statistics: { total: 1, wins: 1, losses: 0, draws: 0 },
  }),
});
beforeEach(() => {
  useAccount.setState({ username: null });
  localStorage.clear();
});
afterEach(() => {
  useAccount.setState({ username: null });
  vi.unstubAllGlobals();
});

describe('server statistics client', () => {
  it('does not save guests or credit a game started in another account', () => {
    const fetch = vi.fn();
    vi.stubGlobal('fetch', fetch);
    useMatchHistory.getState().save(entry);
    useAccount.setState({ username: 'Bob' });
    useMatchHistory.getState().save(entry);
    expect(fetch).not.toHaveBeenCalled();
  });
  it('persists failed submissions for retry after browser closure', async () => {
    useAccount.setState({ username: 'Alice' });
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(Error('offline'))
      .mockImplementation(async () => response());
    vi.stubGlobal('fetch', fetch);
    useMatchHistory.getState().save(entry);
    await useMatchHistory.getState().refresh();
    expect(useMatchHistory.getState().pending).toHaveLength(1);
    expect(useMatchHistory.getState().error).toContain('ещё не сохранена');
    expect(JSON.parse(localStorage.getItem('four-cubed-match-outbox-v1')!)).toHaveLength(1);
    useAccount.setState({ username: 'Bob' });
    expect(useMatchHistory.getState().pending).toHaveLength(0);
    useAccount.setState({ username: 'Alice' });
    expect(useMatchHistory.getState().pending).toHaveLength(1);
    await useMatchHistory.getState().refresh();
    expect(useMatchHistory.getState().pending).toHaveLength(0);
    expect(useMatchHistory.getState().statistics.wins).toBe(1);
    expect(localStorage.getItem('four-cubed-match-history-v1')).toBeNull();
    expect(JSON.parse(localStorage.getItem('four-cubed-match-outbox-v1')!)).toEqual([]);
  });
  it('only reads online results; the browser never submits them', async () => {
    useAccount.setState({ username: 'Alice' });
    const fetch = vi.fn(async () => response());
    vi.stubGlobal('fetch', fetch);
    useMatchHistory.getState().save({ ...entry, mode: 'online' });
    await useMatchHistory.getState().refresh();
    expect(fetch).toHaveBeenCalledWith('/auth/history', expect.objectContaining({ method: 'GET' }));
    expect(fetch).toHaveBeenCalledTimes(1);
  });
  it('ignores a delayed response after logout or account switch', async () => {
    useAccount.setState({ username: 'Alice' });
    let resolve!: (value: ReturnType<typeof response>) => void;
    vi.stubGlobal(
      'fetch',
      vi.fn(
        () =>
          new Promise((done) => {
            resolve = done;
          }),
      ),
    );
    const pending = useMatchHistory.getState().refresh();
    useAccount.setState({ username: 'Bob' });
    resolve(response());
    await pending;
    expect(useMatchHistory.getState().statistics.total).toBe(0);
    expect(useMatchHistory.getState().matches).toEqual([]);
  });
});
