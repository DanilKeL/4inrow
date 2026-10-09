import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';
import { getLevel } from '../game/levels';
import { useAccount } from './accountStore';

type Best = Record<number, number>;
const accountBest = (accounts: Record<string, Best>, owner: string): Best =>
  Object.hasOwn(accounts, owner) ? accounts[owner] : {};
interface LevelProgress {
  best: Best;
  guestBest: Best;
  accounts: Record<string, Best>;
  legacyPending: boolean;
  owner: string | null;
  loading: boolean;
  error: string;
  dirty: boolean;
  record: (id: number, moves: number) => void;
  refresh: () => Promise<void>;
}
const valid = (id: number, moves: unknown): moves is number =>
  Boolean(getLevel(id)) &&
  typeof moves === 'number' &&
  Number.isInteger(moves) &&
  moves > 0 &&
  moves <= 63;
function clean(value: unknown): Best {
  const best: Best = {};
  if (value && typeof value === 'object' && !Array.isArray(value))
    for (const [id, moves] of Object.entries(value))
      if (valid(Number(id), moves)) best[Number(id)] = moves;
  return best;
}
function merge(a: Best, b: Best): Best {
  const best = { ...a };
  for (const [id, moves] of Object.entries(b))
    best[Number(id)] = Math.min(best[Number(id)] ?? Infinity, moves);
  return best;
}
let generation = 0;
let task: Promise<void> | null = null;

export const useLevelProgress = create<LevelProgress>()(
  persist(
    (set, get) => ({
      best: {},
      guestBest: {},
      accounts: {},
      legacyPending: false,
      owner: null,
      loading: false,
      error: '',
      dirty: false,
      record: (id, moves) => {
        if (!valid(id, moves)) return;
        const owner = useAccount.getState().username;
        const current = owner ? accountBest(get().accounts, owner) : get().guestBest;
        if (current[id] !== undefined && current[id] <= moves) return;
        const best = { ...current, [id]: moves };
        if (owner) {
          set({ best, accounts: { ...get().accounts, [owner]: best }, dirty: true });
          void get().refresh();
        } else set({ best, guestBest: best });
      },
      refresh: () => {
        const owner = useAccount.getState().username;
        if (!owner || !navigator.onLine) return Promise.resolve();
        if (task) return task;
        const version = generation;
        set({ loading: true, error: '' });
        task = (async () => {
          try {
            // Repeat if a new win arrives while the previous batch is in flight.
            do {
              const sent = accountBest(get().accounts, owner);
              const response = await fetch('/auth/levels', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ owner, best: sent }),
                signal: AbortSignal.timeout(8000),
              });
              const data = (await response.json()) as {
                username?: string;
                best?: Best;
                error?: string;
              };
              if (!response.ok || data.username !== owner)
                throw new Error(data.error ?? 'Не удалось сохранить уровни.');
              if (version !== generation) return;
              const current = accountBest(get().accounts, owner);
              const best = merge(current, clean(data.best));
              const dirty = Object.entries(best).some(
                ([id, moves]) => data.best?.[Number(id)] !== moves,
              );
              set({ best, accounts: { ...get().accounts, [owner]: best }, dirty });
            } while (get().dirty && version === generation);
          } catch {
            if (version === generation)
              set({
                error: 'Нет связи с сервером. Прогресс будет сохранён при подключении.',
                dirty: true,
              });
          } finally {
            if (version === generation) {
              task = null;
              set({ loading: false });
            }
          }
        })();
        return task;
      },
    }),
    {
      name: 'four-cubed-levels-v1',
      version: 1,
      storage: createJSONStorage(() => ({
        getItem: (name) => {
          try {
            return localStorage.getItem(name);
          } catch {
            return null;
          }
        },
        setItem: (name, value) => {
          try {
            localStorage.setItem(name, value);
          } catch {
            /* Session cache still works. */
          }
        },
        removeItem: (name) => {
          try {
            localStorage.removeItem(name);
          } catch {
            /* Storage is optional. */
          }
        },
      })),
      partialize: (state) => ({
        best: state.guestBest,
        accounts: state.accounts,
        legacyPending: state.legacyPending,
      }),
      merge: (persisted, current) => {
        const saved = persisted as {
          best?: unknown;
          accounts?: Record<string, unknown>;
          legacyPending?: boolean;
        } | null;
        const guestBest = clean(saved?.best);
        const accounts: Record<string, Best> = Object.create(null);
        for (const [owner, best] of Object.entries(saved?.accounts ?? {}))
          accounts[owner] = clean(best);
        const owner = useAccount.getState().username;
        return {
          ...current,
          guestBest,
          accounts,
          owner,
          best: owner ? accountBest(accounts, owner) : guestBest,
          legacyPending:
            saved?.legacyPending ??
            (Boolean(saved) && !saved?.accounts && Object.keys(guestBest).length > 0),
        };
      },
    },
  ),
);

function activate(owner: string | null) {
  generation++;
  task = null;
  const state = useLevelProgress.getState();
  const best = owner
    ? merge(accountBest(state.accounts, owner), state.legacyPending ? state.guestBest : {})
    : state.guestBest;
  useLevelProgress.setState({
    owner,
    best,
    loading: false,
    error: '',
    dirty: Boolean(owner),
    ...(owner ? { accounts: { ...state.accounts, [owner]: best }, legacyPending: false } : {}),
  });
  if (owner) void useLevelProgress.getState().refresh();
}
useAccount.subscribe((state, previous) => {
  if (state.username !== previous.username) activate(state.username);
});
