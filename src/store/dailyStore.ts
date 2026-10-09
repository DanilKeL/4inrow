import { create } from 'zustand';
import type { GameState } from '../game/core';
import {
  type DailyChallenge,
  type DailyResponse,
  dailyDate,
  isDailyChallenge,
} from '../game/daily';
import { useAccount } from './accountStore';

const KEY = 'four-cubed-daily-v1';
interface PendingResult {
  id: string;
  owner: string;
  challengeId: string;
  expiresAt: number;
  moves: { x: number; y: number }[];
}
type Result = {
  id: string;
  status: 'pending' | 'verified' | 'failed' | 'guest';
  error?: string;
  rank?: number;
};
function storedPending(): PendingResult[] {
  try {
    const data: unknown = JSON.parse(localStorage.getItem(KEY) ?? '[]');
    if (!Array.isArray(data)) return [];
    return data
      .filter(
        (item): item is PendingResult =>
          item &&
          typeof item.id === 'string' &&
          typeof item.owner === 'string' &&
          typeof item.challengeId === 'string' &&
          Number.isFinite(item.expiresAt) &&
          Array.isArray(item.moves) &&
          item.moves.length > 0 &&
          item.moves.length <= 63 &&
          item.moves.every(
            (move: { x: number; y: number }) =>
              move &&
              Number.isInteger(move.x) &&
              move.x >= 0 &&
              move.x < 5 &&
              Number.isInteger(move.y) &&
              move.y >= 0 &&
              move.y < 5,
          ),
      )
      .slice(-20);
  } catch {
    return [];
  }
}
function persist(pending: PendingResult[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(pending));
  } catch {
    /* Storage is optional. */
  }
}
interface DailyState {
  challenge: DailyChallenge | null;
  leaderboard: DailyResponse['leaderboard'];
  ownBest: number | null;
  serverOffset: number;
  loading: boolean;
  error: string;
  result: Result | null;
  pending: PendingResult[];
  load: () => Promise<void>;
  saveWin: (id: string, challenge: DailyChallenge, game: GameState, owner: string | null) => void;
  flush: () => Promise<void>;
}
let loading: Promise<void> | null = null;
let sending: Promise<void> | null = null;
export const useDaily = create<DailyState>((set, get) => ({
  challenge: null,
  leaderboard: [],
  ownBest: null,
  serverOffset: 0,
  loading: false,
  error: '',
  result: null,
  pending: storedPending(),
  load: () => {
    if (!navigator.onLine) return Promise.resolve();
    if (loading) return loading;
    const owner = useAccount.getState().username;
    set({ loading: true, error: '' });
    loading = (async () => {
      try {
        const response = await fetch('/daily', {
          cache: 'no-store',
          credentials: 'same-origin',
          signal: AbortSignal.timeout(30000),
        });
        const data = (await response.json()) as DailyResponse & { error?: string };
        if (!response.ok) throw new Error(data.error ?? 'Не удалось загрузить задачу дня.');
        if (
          !isDailyChallenge(data.challenge) ||
          !Array.isArray(data.leaderboard) ||
          !Number.isFinite(data.now)
        )
          throw new Error('Не удалось загрузить задачу дня.');
        if (owner !== useAccount.getState().username) return;
        if (data.username !== owner) {
          await useAccount.getState().load();
          throw new Error('Аккаунт изменился. Повторите загрузку.');
        }
        set({
          challenge: data.challenge,
          leaderboard: data.leaderboard,
          ownBest: data.ownBest,
          serverOffset: data.now - Date.now(),
        });
      } catch (error) {
        set({ error: error instanceof Error ? error.message : 'Нет связи с сервером.' });
      } finally {
        loading = null;
        set({ loading: false });
      }
    })();
    return loading;
  },
  saveWin: (id, challenge, game, owner) => {
    if (game.status !== 'won' || game.winner !== 1) return;
    if (!owner) {
      set({ result: { id, status: 'guest' } });
      return;
    }
    const moves = game.history
      .slice(challenge.preset.length)
      .filter((move) => move.player === 1)
      .map(({ x, y }) => ({ x, y }));
    const entry = { id, challengeId: challenge.id, expiresAt: challenge.expiresAt, moves, owner };
    const pending = [...get().pending.filter((item) => item.id !== id), entry].slice(-20);
    persist(pending);
    set({ pending, result: { id, status: 'pending' } });
    void get().flush();
  },
  flush: () => {
    if (sending) return sending;
    if (!navigator.onLine || !useAccount.getState().identityReady) return Promise.resolve();
    sending = (async () => {
      const owner = useAccount.getState().username;
      if (!owner) return;
      for (;;) {
        const entry = get().pending.find((item) => item.owner === owner);
        if (!entry || owner !== useAccount.getState().username) return;
        const updateResult = (result: Result) => {
          if (get().result?.id === entry.id) set({ result });
        };
        try {
          updateResult({ id: entry.id, status: 'pending' });
          const response = await fetch('/daily/results', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              owner: entry.owner,
              challengeId: entry.challengeId,
              moves: entry.moves,
            }),
            signal: AbortSignal.timeout(30000),
          });
          const data = (await response.json()) as DailyResponse & { rank: number; error?: string };
          if (!response.ok) {
            if ([400, 404, 409, 410, 422].includes(response.status)) {
              const pending = get().pending.filter((item) => item.id !== entry.id);
              persist(pending);
              set({ pending });
            }
            throw new Error(data.error ?? 'Не удалось подтвердить результат.');
          }
          const pending = get().pending.filter((item) => item.id !== entry.id);
          persist(pending);
          set({ pending });
          if (owner === useAccount.getState().username) {
            if (
              (!get().challenge || get().challenge?.id === entry.challengeId) &&
              data.challenge.id === entry.challengeId
            )
              set({
                challenge: data.challenge,
                ownBest: data.ownBest,
                leaderboard: data.leaderboard,
                serverOffset: data.now - Date.now(),
              });
            updateResult({ id: entry.id, status: 'verified', rank: data.rank });
          }
        } catch (error) {
          updateResult({
            id: entry.id,
            status: 'failed',
            error: error instanceof Error ? error.message : 'Нет связи с сервером.',
          });
          return;
        }
      }
    })().finally(() => {
      sending = null;
    });
    return sending;
  },
}));
useAccount.subscribe((state, previous) => {
  if (state.username !== previous.username) {
    useDaily.setState({ ownBest: null, result: null });
    if (state.identityReady && navigator.onLine) void useDaily.getState().load();
  }
});
export function isCurrentDaily(challenge: DailyChallenge | null) {
  return Boolean(
    challenge && challenge.date === dailyDate(Date.now() + useDaily.getState().serverOffset),
  );
}
