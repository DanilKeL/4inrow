import { create } from 'zustand';
import {
  createGame,
  makeMove,
  undo,
  replay,
  getLegalMoves,
  deserialize,
  type GameState,
  type Player,
} from '../game/core';
import { requestBotMove, type Difficulty } from '../game/ai';
import { useSettings } from './settingsStore';
import { playSound } from '../audio/sound';
import { onlineClient, type ConnectionStatus, type OnlineHandlers } from '../network/client';
import type { LobbySnapshot, ClientCommand } from '../network/protocol';
import { onlineElapsed } from '../network/matchTime';
import { useMatchHistory, type SavedMatch } from './matchHistory';
import { currentPlayerName, secondGuestName, useAccount } from './accountStore';
import { prepareMatchAlerts, notifyMatchFound, clearMatchAlert } from '../network/matchAlert';
import { getLevel, levelPosition, levelMoveCount, LEVEL_BOT_OPTIONS } from '../game/levels';
import { useLevelProgress } from './levelStore';
import { readSavedGame, writeSavedGame, removeSavedGame } from './savedGame';
import {
  dailyPosition,
  DAILY_BOT_DIFFICULTY,
  DAILY_BOT_OPTIONS,
  type DailyChallenge,
} from '../game/daily';
import { useDaily } from './dailyStore';

export type Phase =
  | 'menu'
  | 'playing'
  | 'animating'
  | 'ai-thinking'
  | 'paused'
  | 'victory'
  | 'draw'
  | 'replay'
  | 'waiting'
  | 'sending';
export type Mode = 'local' | 'ai' | 'online' | 'level' | 'daily';
interface OnlineSession {
  player: Player;
  snapshot: LobbySnapshot;
}
type QuickMatchState =
  | { status: 'searching' }
  | {
      status: 'found';
      matchId: string;
      opponent: string;
      deadline: number;
      accepted: boolean;
      opponentRating?: number;
      rated?: boolean;
    };
let animationTimer: ReturnType<typeof setTimeout> | undefined;
let botController: AbortController | undefined;
function cancelPending() {
  clearTimeout(animationTimer);
  botController?.abort();
  botController = undefined;
}
interface Store {
  hasSavedGame: boolean;
  resumeSavedGame: () => void;
  discardSavedGame: (recordId: string) => void;
  dailyChallenge: DailyChallenge | null;
  startDaily: (challenge: DailyChallenge) => void;
  levelId: number | null;
  levelBestBefore: number | null;
  startLevel: (id: number) => void;
  game: GameState;
  phase: Phase;
  mode: Mode;
  difficulty: Difficulty;
  names: [string, string];
  elapsed: number;
  xray: boolean;
  layers: number[];
  cameraView: 'perspective' | 'top' | 'front';
  cameraReset: number;
  message: string;
  replayIndex: number;
  matchId: number;
  recordId: string;
  accountAtStart: string | null;
  archiveId: string | null;
  openArchive: (match: SavedMatch) => void;
  online: OnlineSession | null;
  onlineStatus: ConnectionStatus | 'idle';
  onlineError: string;
  onlineKind: 'lobby' | 'quick';
  quickMatch: QuickMatchState | null;
  createOnline: (name: string) => void;
  joinOnline: (code: string, name: string) => void;
  findQuickMatch: (name: string) => void;
  acceptQuickMatch: () => void;
  cancelQuickMatch: () => void;
  restoreOnline: () => void;
  cancelOnline: () => void;
  start: (mode: Mode, difficulty?: Difficulty, names?: [string, string]) => void;
  place: (x: number, y: number) => void;
  settle: () => void;
  pause: () => void;
  requestOnlinePause: () => void;
  answerOnlinePause: (accept: boolean) => void;
  readyOnlinePause: () => void;
  resume: () => void;
  undoMove: () => void;
  restart: () => void;
  menu: () => void;
  tick: () => void;
  toggleXray: () => void;
  toggleLayer: (layer: number) => void;
  showAllLayers: () => void;
  view: (view: 'perspective' | 'top' | 'front') => void;
  openReplay: () => void;
  seek: (index: number) => void;
  closeReplay: () => void;
}

function onlinePhase(snapshot: LobbySnapshot): Phase {
  if (snapshot.game.status !== 'playing')
    return snapshot.game.status === 'won' ? 'victory' : 'draw';
  if (snapshot.pause?.endsAt) return 'paused';
  return snapshot.players.every((player) => player?.connected) ? 'playing' : 'waiting';
}

function receiveOnline(snapshot: LobbySnapshot, player?: Player) {
  const current = useGame.getState();
  const seat = player ?? current.online?.player;
  if (!seat) return;
  if (
    current.online?.snapshot.code === snapshot.code &&
    snapshot.revision < current.online.snapshot.revision
  )
    return;
  const fresh =
    !current.online ||
    current.online.snapshot.code !== snapshot.code ||
    current.online.snapshot.round !== snapshot.round;
  const moved = !fresh && snapshot.game.history.length > current.game.history.length;
  cancelPending();
  useGame.setState({
    mode: 'online',
    levelId: null,
    dailyChallenge: null,
    onlineKind: snapshot.kind === 'quick' ? 'quick' : 'lobby',
    quickMatch: null,
    archiveId: null,
    recordId: `online-${snapshot.code}-${snapshot.startedAt ?? 'waiting'}-${snapshot.round}`,

    online: { player: seat, snapshot },
    onlineError: '',
    message: '',
    game: snapshot.game,
    names: [snapshot.players[0].name, snapshot.players[1]?.name ?? 'Ждём игрока'],
    phase: moved
      ? 'animating'
      : current.phase === 'replay' && !fresh
        ? 'replay'
        : onlinePhase(snapshot),
    elapsed: onlineElapsed(snapshot),
    ...(moved ? { layers: [0, 1, 2, 3, 4] } : {}),
    ...(fresh
      ? {
          layers: [0, 1, 2, 3, 4],
          xray: useSettings.getState().xrayDefault,
          cameraView: 'perspective',
          cameraReset: current.cameraReset + 1,
          matchId: current.matchId + 1,
        }
      : {}),
  });
  saveFinishedMatch();
  if (moved)
    animationTimer = setTimeout(
      () => {
        if (useSettings.getState().sound)
          playSound(snapshot.game.status === 'won' ? 'win' : 'place');
        useGame.getState().settle();
      },
      useSettings.getState().animations ? 440 : 80,
    );
}

const onlineHandlers: OnlineHandlers = {
  onEvent: (event) => {
    if (['session', 'queue', 'queue_removed', 'closed'].includes(event.type)) clearMatchAlert();
    if (event.type === 'session') receiveOnline(event.snapshot, event.player);
    if (event.type === 'state') receiveOnline(event.snapshot);
    if (event.type === 'queue')
      useGame.setState({ quickMatch: { status: 'searching' }, onlineError: '' });
    if (event.type === 'match_found') {
      notifyMatchFound(event.matchId, event.opponent, event.deadline);
      useGame.setState({
        quickMatch: {
          status: 'found',
          matchId: event.matchId,
          opponent: event.opponent,
          deadline: event.deadline,
          accepted: false,
          opponentRating: event.opponentRating,
          rated: event.rated,
        },
        onlineError: '',
      });
    }
    if (event.type === 'queue_removed')
      useGame.setState({ quickMatch: null, onlineError: event.message, onlineStatus: 'error' });
    if (event.type === 'error') {
      useGame.setState({ onlineError: event.message, message: event.message });
      if (useGame.getState().mode === 'online') useGame.getState().settle();
    }
    if (event.type === 'closed') {
      cancelPending();
      useGame.setState({
        onlineStatus: 'error',
        onlineError: event.message,
        message: '',
        phase: useGame.getState().game.status === 'playing' ? 'waiting' : useGame.getState().phase,
      });
    }
  },
  onStatus: (onlineStatus) => {
    if (onlineStatus !== 'connected') clearMatchAlert();
    useGame.setState({
      onlineStatus,
      ...(onlineStatus === 'reconnecting' && useGame.getState().quickMatch
        ? { quickMatch: { status: 'searching' as const }, onlineError: '' }
        : {}),
    });
    if (useGame.getState().mode === 'online') {
      if (onlineStatus === 'connected') useGame.getState().settle();
      else {
        cancelPending();
        if (useGame.getState().game.status === 'playing') useGame.setState({ phase: 'waiting' });
      }
    }
  },
  onFailure: (message) =>
    useGame.setState({ quickMatch: null, onlineError: message, onlineStatus: 'error' }),
};

let connectSequence = 0;
function connectOnline(
  command: Extract<ClientCommand, { type: 'create' | 'join' | 'quick_find' }>,
) {
  if (!navigator.onLine) {
    useGame.setState({
      onlineError: 'Для онлайн-игры нужен интернет.',
      onlineStatus: 'error',
      quickMatch: null,
    });
    return;
  }
  useGame.setState({
    onlineError: '',
    onlineStatus: 'connecting',
    onlineKind: command.type === 'quick_find' ? 'quick' : 'lobby',
    quickMatch: command.type === 'quick_find' ? { status: 'searching' } : null,
  });
  const sequence = ++connectSequence;
  void useAccount
    .getState()
    .load()
    .then(() => {
      if (sequence !== connectSequence) return;
      onlineClient.connect({ ...command, name: currentPlayerName() }, onlineHandlers);
    });
}

export function canPlace(
  state: Pick<Store, 'phase' | 'mode' | 'online' | 'onlineStatus' | 'game'>,
): boolean {
  return (
    state.phase === 'playing' &&
    (state.mode !== 'online' ||
      (state.onlineStatus === 'connected' && state.online?.player === state.game.currentPlayer))
  );
}

function commit(x: number, y: number) {
  const current = useGame.getState();
  const result = makeMove(current.game, x, y);
  if (!result.valid) {
    useGame.setState({ message: 'Столбец заполнен. Выберите другой.' });
    if (useSettings.getState().sound) playSound('invalid');
    return;
  }
  useGame.setState({
    game: result.state,
    phase: 'animating',
    message: '',
    layers: [0, 1, 2, 3, 4],
  });
  saveFinishedMatch();
  animationTimer = setTimeout(
    () => {
      if (useSettings.getState().sound) playSound(result.state.status === 'won' ? 'win' : 'place');
      useGame.getState().settle();
    },
    useSettings.getState().animations ? 440 : 80,
  );
}

function saveFinishedMatch() {
  const { game, names, mode, elapsed, recordId, archiveId, accountAtStart } = useGame.getState();
  if (archiveId || game.status === 'playing') return;
  if (mode === 'daily') {
    const challenge = useGame.getState().dailyChallenge;
    if (challenge && game.winner === 1)
      useDaily.getState().saveWin(recordId, challenge, game, accountAtStart);
    return;
  }
  if (mode === 'level') {
    const level = getLevel(useGame.getState().levelId);
    if (level && game.winner === 1 && accountAtStart === useAccount.getState().username)
      useLevelProgress.getState().record(level.id, levelMoveCount(game, level));
    return;
  }
  useMatchHistory.getState().save({
    id: recordId,
    game,
    names,
    mode,
    elapsed,
    owner: mode === 'online' ? useAccount.getState().username : accountAtStart,
  });
}

export const useGame = create<Store>((set, get) => ({
  dailyChallenge: null,
  startDaily: (challenge) => {
    get().start('ai', DAILY_BOT_DIFFICULTY, [currentPlayerName(), 'FOUR AI']);
    set({
      mode: 'daily',
      dailyChallenge: challenge,
      game: dailyPosition(challenge),
      names: [currentPlayerName(), 'FOUR AI'],
    });
    get().settle();
  },
  hasSavedGame: Boolean(readSavedGame()),
  discardSavedGame: (recordId) => {
    const saved = readSavedGame();
    if (
      get().phase !== 'menu' ||
      !saved ||
      saved.recordId !== recordId ||
      saved.accountAtStart !== useAccount.getState().username
    )
      return;
    removeSavedGame(recordId);
    set({ hasSavedGame: Boolean(readSavedGame()) });
  },
  resumeSavedGame: () => {
    const saved = readSavedGame();
    if (!saved || saved.accountAtStart !== useAccount.getState().username) return;
    onlineClient.leave();
    cancelPending();
    const {
      mode,
      difficulty,
      names,
      elapsed,
      recordId,
      accountAtStart,
      levelId,
      levelBestBefore,
      dailyChallenge,
      xray,
      layers,
      cameraView,
    } = saved;
    set({
      mode,
      difficulty,
      names,
      elapsed,
      recordId,
      accountAtStart,
      levelId,
      levelBestBefore,
      dailyChallenge: dailyChallenge ?? null,
      xray,
      layers,
      cameraView,
      game: saved.restored,
      phase: 'paused',
      online: null,
      onlineStatus: 'idle',
      onlineError: '',
      quickMatch: null,
      archiveId: null,
      message: '',
      cameraReset: get().cameraReset + 1,
      matchId: get().matchId + 1,
    });
    if (saved.mode === 'daily' && navigator.onLine) void useDaily.getState().load();
    get().settle();
  },
  levelId: null,
  levelBestBefore: null,
  startLevel: (id) => {
    const level = getLevel(id);
    if (!level) return;
    get().start('ai', get().difficulty, ['Вы', 'Бот']);
    set({
      mode: 'level',
      levelId: id,
      levelBestBefore: useLevelProgress.getState().best[id] ?? null,
      game: levelPosition(level),
      names: ['Вы', 'Бот'],
      accountAtStart: useAccount.getState().username,
    });
  },
  game: createGame(),
  phase: 'menu',
  mode: 'local',
  difficulty: 'medium',
  names: ['Игрок 1', 'Игрок 2'],
  elapsed: 0,
  xray: false,
  layers: [0, 1, 2, 3, 4],
  cameraView: 'perspective',
  cameraReset: 0,
  message: '',
  replayIndex: 0,
  matchId: 0,
  recordId: '',
  accountAtStart: null,
  archiveId: null,

  openArchive: (match) => {
    const game = deserialize(match.game);
    if (match.endReason && match.winner) {
      game.status = 'won';
      game.winner = match.winner;
    }
    onlineClient.leave();
    cancelPending();
    set({
      game,
      names: match.names,
      elapsed: match.elapsed,
      mode: 'local',
      levelId: null,
      dailyChallenge: null,
      phase: 'replay',
      replayIndex: game.history.length,
      archiveId: match.id,
      recordId: match.id,
      online: null,
      onlineStatus: 'idle',
      onlineError: '',

      message: '',
      layers: [0, 1, 2, 3, 4],
      xray: false,
      cameraView: 'perspective',
      cameraReset: get().cameraReset + 1,
    });
  },
  online: null,
  onlineStatus: 'idle',
  onlineError: '',
  onlineKind: 'lobby',
  quickMatch: null,
  createOnline: (name) => connectOnline({ type: 'create', name }),
  joinOnline: (code, name) =>
    connectOnline({ type: 'join', code: code.trim().toUpperCase(), name }),
  findQuickMatch: (name) => {
    prepareMatchAlerts();
    connectOnline({ type: 'quick_find', name });
  },
  acceptQuickMatch: () => {
    clearMatchAlert();
    const match = get().quickMatch;
    if (match?.status !== 'found' || match.accepted || Date.now() >= match.deadline) return;
    if (onlineClient.send({ type: 'quick_accept', matchId: match.matchId }))
      set({ quickMatch: { ...match, accepted: true } });
  },
  cancelQuickMatch: () => {
    clearMatchAlert();
    connectSequence++;
    if (get().quickMatch) onlineClient.send({ type: 'quick_cancel' });
    onlineClient.disconnect();
    set({ quickMatch: null, onlineStatus: 'idle', onlineError: '' });
  },
  restoreOnline: () => {
    if (!navigator.onLine) return;
    if (get().mode === 'online' || get().onlineStatus === 'connecting') return;
    if (onlineClient.restore(onlineHandlers)) {
      if (onlineClient.isSearching)
        set({ onlineKind: 'quick', quickMatch: { status: 'searching' } });
      else set({ mode: 'online', phase: 'waiting' });
    }
  },
  cancelOnline: () => {
    clearMatchAlert();
    connectSequence++;
    onlineClient.disconnect();
    set({ onlineStatus: 'idle', onlineError: '', quickMatch: null });
  },
  start: (
    mode,
    difficulty = get().difficulty,
    names = [currentPlayerName(), secondGuestName()],
  ) => {
    if (mode === 'online' || mode === 'level' || mode === 'daily') return;
    onlineClient.leave();
    cancelPending();
    set({
      game: createGame(),
      phase: 'playing',
      mode,
      levelId: null,
      levelBestBefore: null,
      dailyChallenge: null,
      recordId: `local-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      accountAtStart: useAccount.getState().username,
      archiveId: null,

      online: null,
      onlineStatus: 'idle',
      onlineError: '',
      quickMatch: null,
      difficulty,
      names: [
        names[0].trim() || 'Игрок 1',
        mode === 'ai' ? 'FOUR AI' : names[1].trim() || 'Игрок 2',
      ],
      elapsed: 0,
      message: '',
      layers: [0, 1, 2, 3, 4],
      xray: useSettings.getState().xrayDefault,
      cameraView: 'perspective',
      cameraReset: get().cameraReset + 1,
      matchId: get().matchId + 1,
    });
    try {
      localStorage.setItem('four-cubed-difficulty', difficulty);
    } catch {
      /* Storage can be unavailable in private browsing. */
    }
  },
  place: (x, y) => {
    if (get().mode === 'online') {
      if (!canPlace(get()) || !get().online) return;
      const { revision, round } = get().online!.snapshot;
      if (onlineClient.send({ type: 'move', x, y, revision, round })) {
        set({ phase: 'sending', message: '', onlineError: '' });
        // A dropped acknowledgment is resolved by resuming the authoritative snapshot, never replaying a move.
        animationTimer = setTimeout(() => {
          if (get().phase === 'sending') onlineClient.restore(onlineHandlers);
        }, 8000);
      }
      return;
    }
    if (
      get().phase !== 'playing' ||
      (['ai', 'level', 'daily'].includes(get().mode) && get().game.currentPlayer === 2)
    )
      return;
    commit(x, y);
  },
  settle: () => {
    if (get().mode === 'online') {
      const { online, onlineStatus } = get();
      set({
        phase: online && onlineStatus === 'connected' ? onlinePhase(online.snapshot) : 'waiting',
      });
      return;
    }
    const { game, mode, difficulty } = get();
    if (game.status !== 'playing') {
      set({ phase: game.status === 'won' ? 'victory' : 'draw' });
      return;
    }
    if (!['ai', 'level', 'daily'].includes(mode) || game.currentPlayer !== 2) {
      set({ phase: 'playing' });
      return;
    }
    set({ phase: 'ai-thinking' });
    const controller = new AbortController();
    botController = controller;
    const delay = new Promise<void>((resolve) => {
      animationTimer = setTimeout(resolve, 420);
    });
    void Promise.all([
      requestBotMove(
        game,
        mode === 'daily' ? DAILY_BOT_DIFFICULTY : mode === 'level' ? 'medium' : difficulty,
        controller.signal,
        mode === 'daily' ? DAILY_BOT_OPTIONS : mode === 'level' ? LEVEL_BOT_OPTIONS : undefined,
      ),
      delay,
    ])
      .then(([move]) => {
        if (controller.signal.aborted || get().phase !== 'ai-thinking' || get().game !== game)
          return;
        if (
          !move ||
          !getLegalMoves(game).some((legal) => legal.x === move.x && legal.y === move.y)
        ) {
          throw new Error('AI returned no legal move for an active game');
        }
        commit(move.x, move.y);
      })
      .catch((error: unknown) => {
        if (controller.signal.aborted) return;
        console.error('AI calculation failed', error);
        set({
          phase: 'paused',
          message: 'Не удалось рассчитать ход. Нажмите «Продолжить», чтобы повторить.',
        });
      });
  },
  pause: () => {
    if (get().mode === 'online') return;
    if (!['playing', 'animating', 'ai-thinking'].includes(get().phase)) return;
    cancelPending();
    set({ phase: 'paused' });
  },
  requestOnlinePause: () => {
    const { online, onlineStatus, mode } = get();
    if (mode === 'online' && online && onlineStatus === 'connected')
      onlineClient.send({ type: 'pause_request', round: online.snapshot.round });
  },
  readyOnlinePause: () => {
    const { online, onlineStatus, mode } = get();
    if (mode === 'online' && online?.snapshot.pause?.endsAt && onlineStatus === 'connected')
      onlineClient.send({ type: 'pause_ready', round: online.snapshot.round });
  },
  answerOnlinePause: (accept) => {
    const { online, onlineStatus, mode } = get();
    const request = online?.snapshot.pause?.request;
    if (mode === 'online' && online && request && onlineStatus === 'connected')
      onlineClient.send({
        type: 'pause_answer',
        round: online.snapshot.round,
        requestId: request.id,
        accept,
      });
  },
  resume: () => {
    if (get().phase === 'paused') get().settle();
  },
  undoMove: () => {
    if (['online', 'level', 'daily'].includes(get().mode)) return;
    if (get().phase !== 'playing' || get().game.history.length === 0) return;
    cancelPending();
    let game = undo(get().game);
    if (get().mode === 'ai' && game.currentPlayer === 2) game = undo(game);
    set({ game, message: '', layers: [0, 1, 2, 3, 4] });
    get().settle();
  },
  restart: () => {
    if (get().mode === 'daily' && get().dailyChallenge) {
      get().startDaily(get().dailyChallenge!);
      return;
    }
    if (get().mode === 'level' && get().levelId !== null) {
      get().startLevel(get().levelId!);
      return;
    }
    if (get().mode === 'online') {
      if (get().online && get().game.status !== 'playing')
        onlineClient.send({ type: 'rematch', round: get().online!.snapshot.round });
      return;
    }
    get().start(get().mode, get().difficulty, get().names);
  },
  menu: () => {
    onlineClient.leave();
    cancelPending();
    const current = get();
    if (current.phase !== 'menu' && current.mode !== 'online' && !current.archiveId)
      removeSavedGame(current.recordId);
    set({
      phase: 'menu',
      hasSavedGame: Boolean(readSavedGame()),
      mode: 'local',
      levelId: null,
      dailyChallenge: null,
      archiveId: null,

      message: '',
      online: null,
      onlineStatus: 'idle',
      onlineError: '',
      quickMatch: null,
    });
  },
  tick: () => {
    if (get().mode === 'online') {
      if (get().onlineStatus === 'error') return;
      const snapshot = get().online?.snapshot;
      if (snapshot?.startedAt && !snapshot.finishedAt) set({ elapsed: onlineElapsed(snapshot) });
      return;
    }
    if (['playing', 'animating', 'ai-thinking'].includes(get().phase))
      set({ elapsed: get().elapsed + 1 });
  },
  toggleXray: () => set({ xray: !get().xray }),
  toggleLayer: (layer) => {
    if (!Number.isInteger(layer) || layer < 0 || layer > 4) return;
    set(({ layers }) => ({
      layers: layers.includes(layer)
        ? layers.filter((z) => z !== layer)
        : [...layers, layer].sort((a, b) => a - b),
    }));
  },
  showAllLayers: () => set({ layers: [0, 1, 2, 3, 4] }),
  view: (cameraView) => set({ cameraView, cameraReset: get().cameraReset + 1 }),
  openReplay: () => {
    cancelPending();
    set({ phase: 'replay', replayIndex: get().game.history.length });
  },
  seek: (index) =>
    set({
      replayIndex: Number.isFinite(index)
        ? Math.max(0, Math.min(Math.floor(index), get().game.history.length))
        : 0,
    }),
  closeReplay: () => {
    if (get().archiveId) {
      get().menu();
      return;
    }
    set({
      phase:
        get().game.status === 'won' ? 'victory' : get().game.status === 'draw' ? 'draw' : 'paused',
    });
  },
}));

export function displayedGame(state: Store): GameState {
  return state.phase === 'replay' ? replay(state.game.history, state.replayIndex) : state.game;
}

function persistActiveGame() {
  const state = useGame.getState();
  if (state.mode === 'online' || state.archiveId) return;
  if (state.game.status !== 'playing') removeSavedGame(state.recordId);
  else if (['playing', 'animating', 'ai-thinking', 'paused'].includes(state.phase)) {
    const {
      mode,
      game,
      difficulty,
      names,
      elapsed,
      recordId,
      accountAtStart,
      levelId,
      levelBestBefore,
      dailyChallenge,
      xray,
      layers,
      cameraView,
    } = state;
    writeSavedGame({
      mode,
      game,
      difficulty,
      names,
      elapsed,
      recordId,
      accountAtStart,
      levelId,
      levelBestBefore,
      dailyChallenge,
      xray,
      layers,
      cameraView,
    });
  }
  const exists = Boolean(readSavedGame());
  if (state.hasSavedGame !== exists) useGame.setState({ hasSavedGame: exists });
}
useGame.subscribe((state, previous) => {
  if (
    state.game !== previous.game ||
    state.phase !== previous.phase ||
    state.layers !== previous.layers ||
    state.xray !== previous.xray ||
    state.cameraView !== previous.cameraView ||
    Math.floor(state.elapsed / 5) !== Math.floor(previous.elapsed / 5)
  )
    persistActiveGame();
});
if (typeof window !== 'undefined') {
  window.addEventListener('pagehide', persistActiveGame);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) persistActiveGame();
  });
}
