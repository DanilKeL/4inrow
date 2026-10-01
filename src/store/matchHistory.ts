import { create } from 'zustand';
import { serialize, type GameState } from '../game/core';
import { useAccount } from './accountStore';
import type { HistoryResponse, SavedMatch, Statistics } from '../network/statistics';
export type { SavedMatch } from '../network/statistics';

type PendingMatch = Omit<SavedMatch, 'title' | 'date'> & { owner: string };
const emptyStatistics = (): Statistics => ({ total: 0, wins: 0, losses: 0, draws: 0 });
let generation = 0;
let loadingTask: Promise<void> | null = null;

async function request(owner: string, action = '', body?: object): Promise<HistoryResponse> {
  const response = await fetch(`/auth/history${action}`, {
    method: body ? 'POST' : 'GET',
    credentials: 'same-origin',
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify({ ...body, owner }) : undefined,
    signal: AbortSignal.timeout(8000),
  });
  const data = (await response.json()) as HistoryResponse & { error?: string };
  if (!response.ok) throw new Error(data.error ?? 'Не удалось загрузить статистику.');
  if (data.username !== owner) throw new Error('Аккаунт изменился. Обновите страницу.');
  return data;
}

interface HistoryState {
  matches: SavedMatch[];
  statistics: Statistics;
  rating: HistoryResponse['rating'];
  pending: PendingMatch[];
  loading: boolean;
  error: string;
  refresh: () => Promise<void>;
  save: (
    entry: Omit<SavedMatch, 'game' | 'title' | 'date'> & { game: GameState; owner: string | null },
  ) => void;
  rename: (id: string, title: string) => Promise<void>;
  remove: (id: string) => Promise<void>;
}
export const useMatchHistory = create<HistoryState>((set, get) => ({
  matches: [],
  statistics: emptyStatistics(),
  rating: { points: 1000, games: 0 },
  pending: [],
  loading: false,
  error: '',
  refresh: () => {
    const owner = useAccount.getState().username;
    if (!owner) return Promise.resolve();
    if (loadingTask) return loadingTask;
    const version = generation;
    set({ loading: true, error: '' });
    loadingTask = (async () => {
      try {
        while (get().pending.length && version === generation) {
          const entry = get().pending[0];
          await request(owner, '', entry);
          if (version !== generation) return;
          set({ pending: get().pending.filter((item) => item.id !== entry.id) });
        }
        if (version !== generation) return;
        const data = await request(owner);
        if (version === generation)
          set({
            matches: data.matches,
            statistics: data.statistics,
            rating: data.rating ?? { points: 1000, games: 0 },
          });
      } catch (error) {
        if (version === generation)
          set({
            error: get().pending.length
              ? 'Партия ещё не сохранена на сервере. Нажмите «Повторить» до закрытия страницы.'
              : error instanceof Error
                ? error.message
                : 'Нет связи с сервером.',
          });
      } finally {
        if (version === generation) {
          loadingTask = null;
          set({ loading: false });
          if (get().pending.length && !get().error) void get().refresh();
        }
      }
    })();
    return loadingTask;
  },
  save: (entry) => {
    const owner = useAccount.getState().username;
    if (!owner || owner !== entry.owner || entry.game.status === 'playing') return;
    if (entry.mode !== 'online' && !get().pending.some((match) => match.id === entry.id)) {
      set({ pending: [...get().pending, { ...entry, owner, game: serialize(entry.game) }] });
    }
    void get().refresh();
  },
  rename: (id, title) => mutate('/rename', { id, title }),
  remove: (id) => mutate('/remove', { id }),
}));

async function mutate(action: string, body: object) {
  const owner = useAccount.getState().username;
  if (!owner) return;
  const version = generation;
  if (loadingTask) await loadingTask;
  if (version !== generation) return;
  useMatchHistory.setState({ loading: true, error: '' });
  try {
    const data = await request(owner, action, body);
    if (version === generation)
      useMatchHistory.setState({
        matches: data.matches,
        statistics: data.statistics,
        rating: data.rating ?? { points: 1000, games: 0 },
      });
  } catch (error) {
    if (version === generation)
      useMatchHistory.setState({
        error: error instanceof Error ? error.message : 'Нет связи с сервером.',
      });
  } finally {
    if (version === generation) useMatchHistory.setState({ loading: false });
  }
}

useAccount.subscribe((state, previous) => {
  if (state.username === previous.username) return;
  generation++;
  loadingTask = null;
  useMatchHistory.setState({
    matches: [],
    statistics: emptyStatistics(),
    rating: { points: 1000, games: 0 },
    pending: [],
    error: '',
    loading: false,
  });
});
