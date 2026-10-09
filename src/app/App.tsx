import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useState,
  useSyncExternalStore,
} from 'react';
import {
  ArrowRight,
  ChevronDown,
  CircleHelp,
  Cuboid,
  Cpu,
  Eye,
  Home,
  Layers3,
  Maximize,
  Pause,
  RotateCcw,
  Settings2,
  UsersRound,
  Volume2,
  VolumeX,
  Globe2,
  Search,
  X,
  UserRound,
  Puzzle,
  Play,
  Trophy,
} from 'lucide-react';
import { MotionConfig, useReducedMotion } from 'motion/react';
import { createGame, type GameState, type Move } from '../game/core';
import { canPlace, displayedGame, useGame, type Mode } from '../store/gameStore';
import { useSettings } from '../store/settingsStore';
import { currentPlayerName, useAccount } from '../store/accountStore';
import { unlockAudio } from '../audio/sound';
import { Dialog } from '../ui/Dialog';
import { Setup } from '../ui/Setup';
import { Settings } from '../ui/Settings';
import { Tutorial } from '../ui/Tutorial';
import { GamePanel } from '../ui/GamePanel';
import { ErrorBoundary } from '../ui/ErrorBoundary';
import { OnlineLobby } from '../ui/OnlineLobby';
import { OnlinePause } from '../ui/OnlinePause';
import { LoadingScreen } from '../ui/LoadingScreen';
import { MatchHistory } from '../ui/MatchHistory';
import { QuickMatch } from '../ui/QuickMatch';
import { Account } from '../ui/Account';
import { Levels } from '../ui/Levels';
import { TurnTimer } from '../ui/TurnTimer';
import { RankedResult } from '../ui/RankedResult';
import { Leaderboard } from '../ui/Leaderboard';
import { useLevelProgress } from '../store/levelStore';
import { useMatchHistory } from '../store/matchHistory';
import { getLevel, levelMoveCount, moveLabel } from '../game/levels';
import {
  preloadTutorialMedia,
  subscribeTutorialMedia,
  tutorialMediaSnapshot,
} from '../network/tutorialMedia';
import styles from '../ui/UI.module.css';
import { useOffline, applyOfflineUpdate, retryOffline } from '../network/offline';
import { readSavedGame } from '../store/savedGame';

const GameScene = lazy(() => import('../scene/GameScene'));
type Overlay =
  | 'setup'
  | 'settings'
  | 'tutorial'
  | 'pause'
  | 'online-pause'
  | 'leave'
  | 'restart'
  | 'leave-online'
  | 'history'
  | 'quick'
  | 'account'
  | 'levels'
  | 'leaderboard'
  | null;

function demoGame(): GameState {
  const game = createGame();
  const stacks: [number, number, (1 | 2)[]][] = [
    [0, 0, [1]],
    [2, 0, [2]],
    [3, 0, [1, 2]],
    [4, 0, [2]],
    [0, 1, [2, 1]],
    [1, 1, [1]],
    [3, 1, [2, 1, 2]],
    [4, 1, [1]],
    [1, 2, [2, 1, 1]],
    [2, 2, [1, 2, 1, 2]],
    [4, 2, [2, 2]],
    [0, 3, [1]],
    [2, 3, [2, 1]],
    [3, 3, [1, 2, 1]],
    [4, 4, [2]],
    [1, 4, [2]],
    [2, 4, [1]],
  ];
  stacks.forEach(([x, y, players]) =>
    players.forEach((player, z) => {
      const move: Move = { x, y, z, player, index: game.history.length };
      game.board[x + y * 5 + z * 25] = player;
      game.heights[x + y * 5] = z + 1;
      game.history.push(move);
    }),
  );
  return game;
}

export default function App() {
  const state = useGame();
  const offline = useOffline();
  const username = useAccount((account) => account.username);
  const saved = state.hasSavedGame ? readSavedGame() : null;
  const canContinue = saved && saved.accountAtStart === username;
  useEffect(() => {
    const sync = () => {
      if (!navigator.onLine) return;
      void useAccount
        .getState()
        .load()
        .then(() => {
          void useLevelProgress.getState().refresh();
          void useMatchHistory.getState().refresh();
        });
    };
    const retry = () => {
      if (useLevelProgress.getState().dirty || useMatchHistory.getState().pending.length) sync();
    };
    window.addEventListener('online', sync);
    window.addEventListener('focus', sync);
    const timer = window.setInterval(retry, 30_000);
    sync();
    return () => {
      window.removeEventListener('online', sync);
      window.removeEventListener('focus', sync);
      window.clearInterval(timer);
    };
  }, []);
  const accountName = useAccount((account) => account.username ?? account.guestName);
  const settings = useSettings();
  const reducedMotion = useReducedMotion();
  const [sceneReady, setSceneReady] = useState(false);
  const [fontsReady, setFontsReady] = useState(false);
  const [loadingFailed, setLoadingFailed] = useState(false);
  const media = useSyncExternalStore(subscribeTutorialMedia, tutorialMediaSnapshot);
  const [skipVideos, setSkipVideos] = useState(false);
  const ready = sceneReady && fontsReady && (media.ready || skipVideos);
  const handleSceneReady = useCallback(() => setSceneReady(true), []);
  const handleSceneError = useCallback(() => setLoadingFailed(true), []);
  useEffect(() => {
    let mounted = true;
    void preloadTutorialMedia();
    void document.fonts.ready.then(() => {
      if (mounted) setFontsReady(true);
    });
    return () => {
      mounted = false;
    };
  }, []);
  const [overlay, setOverlay] = useState<Overlay>(() => {
    const query = new URLSearchParams(window.location.search);
    return query.has('reset') || query.has('emailVerified') ? 'account' : null;
  });
  const [setupMode, setSetupMode] = useState<Mode>('local');
  const [quickName, setQuickName] = useState('Игрок');
  const [viewMenu, setViewMenu] = useState(false);
  const [afterTutorial, setAfterTutorial] = useState(false);
  const [selectedLevel, setSelectedLevel] = useState(1);
  const level = getLevel(state.levelId);
  const openLevels = () => {
    if (state.levelId) setSelectedLevel(state.levelId);
    state.menu();
    setOverlay('levels');
  };
  const pauseIdentity =
    state.mode === 'online' && state.onlineStatus !== 'error'
      ? (state.online?.snapshot.pause?.request?.id ?? state.online?.snapshot.pause?.endsAt)
      : undefined;
  useEffect(() => {
    if (pauseIdentity) setOverlay('online-pause');
    else setOverlay((current) => (current === 'online-pause' ? null : current));
  }, [pauseIdentity]);
  const isMenu = state.phase === 'menu';
  const demo = useMemo(demoGame, []);
  const shown = useMemo(() => (isMenu ? demo : displayedGame(state)), [isMenu, demo, state]);
  const closeOverlay = useCallback(() => {
    if (useGame.getState().mode !== 'online' && useGame.getState().onlineStatus !== 'idle')
      useGame.getState().cancelOnline();
    setOverlay(null);
    if (useGame.getState().phase === 'paused') useGame.getState().resume();
  }, []);
  const openSetup = (mode: Mode) => {
    setSetupMode(mode);
    setOverlay('setup');
  };
  const beginQuick = (name?: string) => {
    const playerName = name ?? currentPlayerName();
    setQuickName(playerName);
    setOverlay('quick');
    useGame.getState().findQuickMatch(playerName);
  };
  useEffect(() => {
    if (overlay === 'quick' && state.mode === 'online' && state.online) setOverlay(null);
  }, [overlay, state.mode, state.online]);
  useEffect(() => {
    if (state.quickMatch) setOverlay('quick');
  }, [state.quickMatch]);
  const openSettings = () => {
    state.pause();
    setOverlay('settings');
  };
  const openTutorial = () => {
    state.pause();
    setAfterTutorial(false);
    setOverlay('tutorial');
  };
  const requestMenu = () => {
    if (state.mode === 'online') {
      setOverlay('leave-online');
      return;
    }
    if (state.game.status === 'playing' && state.game.history.length > 0) {
      state.pause();
      setOverlay('leave');
    } else {
      state.menu();
      setOverlay(null);
    }
  };
  useEffect(() => {
    void useAccount.getState().load();
    useGame.getState().restoreOnline();
    const timer = setInterval(() => useGame.getState().tick(), 1000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (event.target instanceof HTMLInputElement || overlay) return;
      const game = useGame.getState();
      if (event.key === 'Escape' && game.phase !== 'menu') {
        game.pause();
        setOverlay('pause');
      }
      if (event.key.toLowerCase() === 'r') game.view('perspective');
      if (event.key.toLowerCase() === 'x') game.toggleXray();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [overlay]);

  const turnText =
    state.phase === 'ai-thinking'
      ? level
        ? 'Ход бота…'
        : 'AI обдумывает ход…'
      : state.phase === 'animating'
        ? 'Ход выполнен'
        : state.phase === 'paused'
          ? 'Пауза'
          : state.phase === 'replay'
            ? `Повтор · ход ${state.replayIndex}`
            : state.game.status !== 'playing'
              ? 'Партия завершена'
              : state.mode === 'online'
                ? state.onlineStatus !== 'connected'
                  ? 'Нет соединения'
                  : state.phase === 'waiting'
                    ? 'Ждём соперника'
                    : state.phase === 'sending'
                      ? 'Отправляем ход…'
                      : state.online?.player === state.game.currentPlayer
                        ? 'Ваш ход'
                        : 'Ход соперника'
                : level
                  ? 'Ваш ход'
                  : `Ходит ${state.names[state.game.currentPlayer - 1]}`;

  return (
    <MotionConfig reducedMotion={settings.animations ? 'user' : 'always'}>
      <LoadingScreen
        ready={ready}
        failed={loadingFailed}
        mediaProgress={!media.ready && !skipVideos ? `${media.loaded}/${media.total}` : undefined}
        onSkipVideos={() => setSkipVideos(true)}
      />
      <div
        inert={!ready || loadingFailed}
        aria-busy={!ready}
        className={styles.app}
        onPointerDown={() => {
          try {
            unlockAudio();
          } catch {
            /* Audio is optional on browsers without Web Audio. */
          }
        }}
      >
        <header className={styles.header}>
          <button
            className={styles.brand}
            onClick={() => {
              if (!isMenu) requestMenu();
            }}
            aria-label="FOUR³ — главное меню"
          >
            FOUR<sup>3</sup>
          </button>
          <nav className={styles.headerActions} aria-label="Основная навигация">
            <button
              className={styles.accountButton}
              onClick={() => setOverlay('account')}
              aria-label={`Аккаунт: ${accountName}`}
            >
              <UserRound size={18} />
              <span>{accountName}</span>
            </button>
            <button onClick={openTutorial} className={styles.helpButton} aria-label="Как играть">
              <CircleHelp size={18} />
              <span>Как играть</span>
            </button>
            <span className={styles.divider} />
            <button
              className={styles.iconButton}
              onClick={() => settings.set('sound', !settings.sound)}
              aria-label={settings.sound ? 'Выключить звук' : 'Включить звук'}
            >
              {settings.sound ? <Volume2 size={19} /> : <VolumeX size={19} />}
            </button>
            <button className={styles.iconButton} aria-label="Настройки" onClick={openSettings}>
              <Settings2 size={19} />
            </button>
          </nav>
        </header>

        <main className={`${styles.main} ${isMenu ? styles.menuMain : styles.playMain}`}>
          {isMenu ? (
            <section className={styles.hero} aria-label="Режимы игры">
              <h1>Четыре в ряд</h1>
              <p className={styles.heroSubtitle}>
                Классическая игра в новом
                <br />
                трёхмерном измерении
              </p>
              <button
                className={styles.primary + ' ' + styles.playButton}
                disabled={!offline.online && !canContinue}
                onClick={() => (canContinue ? state.resumeSavedGame() : beginQuick())}
              >
                {canContinue ? <Play size={19} /> : <Search size={19} />}
                {canContinue ? 'Продолжить партию' : 'Рейтинговая игра'} <ArrowRight size={19} />
              </button>
              {canContinue && offline.online && (
                <button className={styles.resumeAlternate} onClick={() => beginQuick()}>
                  <Search size={15} /> Рейтинговая игра <ArrowRight size={15} />
                </button>
              )}
              <div className={styles.quickModes}>
                <button onClick={openLevels}>
                  <Puzzle size={19} />
                  <span>Уровни</span>
                  <ArrowRight size={16} />
                </button>
                <button onClick={() => openSetup('ai')}>
                  <Cpu size={19} />
                  <span>Против AI</span>
                  <ArrowRight size={16} />
                </button>
                <button onClick={() => openSetup('local')}>
                  <UsersRound size={19} />
                  <span>Вдвоём</span>
                  <ArrowRight size={16} />
                </button>
                <button
                  onClick={() => openSetup('online')}
                  disabled={!offline.online}
                  title={!offline.online ? 'Нужен интернет' : undefined}
                >
                  <Globe2 size={19} />
                  <span>Онлайн</span>
                  <ArrowRight size={16} />
                </button>
              </div>
              <button
                className={styles.leaderboardButton}
                disabled={!offline.online}
                onClick={() => setOverlay('leaderboard')}
              >
                <Trophy size={18} />
                <span>Рейтинг игроков</span>
                <ArrowRight size={16} />
              </button>
              <div className={styles.offlineStatus} role="status" data-testid="offline-status">
                {!offline.online
                  ? offline.ready
                    ? 'Без интернета · боты и уровни доступны'
                    : 'Без интернета'
                  : offline.error && !offline.ready
                    ? 'Не удалось сохранить игру для офлайна'
                    : offline.saving && !offline.ready
                      ? `Сохраняем для офлайна${offline.total ? ` · ${Math.round((offline.loaded / offline.total) * 100)}%` : '…'}`
                      : offline.ready
                        ? 'Доступно без интернета'
                        : null}
                {offline.online && offline.error && !offline.ready && (
                  <button onClick={retryOffline}>Повторить</button>
                )}
                {offline.online && offline.update && (
                  <button onClick={applyOfflineUpdate}>Обновить игру</button>
                )}
              </div>
            </section>
          ) : (
            <GamePanel onMenu={requestMenu} onLevels={openLevels} />
          )}

          <section className={styles.boardArea} aria-label="Игровое поле">
            {!isMenu && state.mode === 'online' && <OnlineLobby onLeave={requestMenu} />}
            <div className={styles.boardTop}>
              {isMenu ? (
                <>
                  <span className={styles.dimension}>
                    <Cuboid size={14} /> 5 × 5 × 5
                  </span>
                </>
              ) : (
                <>
                  <div className={styles.turnPill} data-testid="turn-status" aria-live="polite">
                    <span
                      className={`${styles.turnToken} ${state.game.currentPlayer === 2 ? styles.lightTurn : ''}`}
                    />
                    <span className={styles.turnLabel}>
                      {level && `Уровень ${level.id} · `}
                      {turnText}
                    </span>
                    {state.mode === 'online' && !pauseIdentity && <TurnTimer />}
                  </div>
                  <button
                    className={styles.iconButton}
                    aria-label="Пауза"
                    onClick={() => {
                      if (pauseIdentity) {
                        setOverlay('online-pause');
                        return;
                      }
                      state.pause();
                      setOverlay('pause');
                    }}
                  >
                    <Pause size={19} />
                  </button>
                </>
              )}
            </div>
            <div className={styles.canvasWrap} onContextMenu={(event) => event.preventDefault()}>
              <ErrorBoundary onError={handleSceneError}>
                <Suspense
                  fallback={
                    <div className={styles.loading}>
                      <span className={styles.loadingRing} />
                      Готовим поле…
                    </div>
                  }
                >
                  <GameScene
                    game={shown}
                    onPlace={state.place}
                    interactive={!isMenu && canPlace(state) && !overlay}
                    xray={!isMenu && state.xray}
                    layers={isMenu ? [0, 1, 2, 3, 4] : state.layers}
                    cameraView={state.cameraView}
                    cameraReset={state.cameraReset}
                    animations={settings.animations && !reducedMotion}
                    hints={settings.hints}
                    demo={isMenu}
                    revealed={ready}
                    onReady={handleSceneReady}
                    onError={handleSceneError}
                  />
                </Suspense>
              </ErrorBoundary>
            </div>
            {!isMenu && (
              <div className={styles.mobilePlayers}>
                <span>● {state.names[0]}</span>
                <strong>
                  {level
                    ? moveLabel(levelMoveCount(state.game, level))
                    : `${state.phase === 'replay' ? state.replayIndex : state.game.history.length} ходов`}
                </strong>
                <span>○ {state.names[1]}</span>
              </div>
            )}
            {state.message && !isMenu && (
              <p role="status" className={styles.feedback}>
                {state.message}
              </p>
            )}
            <div className={styles.boardBottom}>
              <div className={styles.boardTools}>
                {!isMenu && !level && (
                  <button
                    aria-label="Отменить ход"
                    title="Отменить ход"
                    className={styles.toolButton}
                    disabled={
                      state.mode === 'online' ||
                      state.phase !== 'playing' ||
                      !state.game.history.length
                    }
                    onClick={state.undoMove}
                  >
                    <RotateCcw size={18} />
                    <span>Отменить</span>
                  </button>
                )}
                {!isMenu && (
                  <button
                    aria-label="Рентген"
                    aria-pressed={state.xray}
                    className={`${styles.toolButton} ${state.xray ? styles.toolActive : ''}`}
                    onClick={state.toggleXray}
                  >
                    <Eye size={18} />
                    <span>Рентген</span>
                  </button>
                )}
                {!isMenu && (
                  <div className={styles.viewControl}>
                    <button
                      className={styles.toolButton}
                      onClick={() => setViewMenu(!viewMenu)}
                      aria-expanded={viewMenu}
                      aria-label="Вид"
                    >
                      <Layers3 size={18} />
                      <span>Вид</span>
                      <ChevronDown size={13} />
                    </button>
                    {viewMenu && (
                      <div className={styles.viewPopover}>
                        <div className={styles.viewHeading}>
                          <strong>Камера</strong>
                          <button
                            className={styles.iconButton}
                            aria-label="Закрыть меню вида"
                            onClick={() => setViewMenu(false)}
                          >
                            <X size={18} />
                          </button>
                        </div>
                        <div className={styles.cameraChoices}>
                          {(
                            [
                              ['perspective', '3D'],
                              ['top', 'Сверху'],
                              ['front', 'Спереди'],
                            ] as const
                          ).map(([value, label]) => (
                            <button
                              key={value}
                              className={state.cameraView === value ? styles.selected : ''}
                              onClick={() => state.view(value)}
                            >
                              {label}
                            </button>
                          ))}
                        </div>
                        <strong>Показать слои</strong>
                        <div className={styles.layerChoices}>
                          {[null, 0, 1, 2, 3, 4].map((layer) => (
                            <button
                              key={layer ?? 'all'}
                              aria-label={layer === null ? 'Все слои' : `Слой ${layer + 1}`}
                              aria-pressed={
                                layer === null
                                  ? state.layers.length === 5
                                  : state.layers.includes(layer)
                              }
                              className={
                                (
                                  layer === null
                                    ? state.layers.length === 5
                                    : state.layers.includes(layer)
                                )
                                  ? styles.selected
                                  : ''
                              }
                              onClick={() =>
                                layer === null ? state.showAllLayers() : state.toggleLayer(layer)
                              }
                            >
                              {layer === null ? 'Все' : layer + 1}
                            </button>
                          ))}
                        </div>
                        <small>
                          Включайте и скрывайте каждый слой отдельно.
                          <br />
                          Новый ход вернёт все слои.
                        </small>
                      </div>
                    )}
                  </div>
                )}
                <button
                  className={styles.toolButton}
                  aria-label="Сбросить вид"
                  title="Сбросить вид · R"
                  onClick={() => {
                    state.view('perspective');
                    setViewMenu(false);
                  }}
                >
                  <Maximize size={17} />
                  <span>{isMenu ? 'Сбросить вид' : ''}</span>
                </button>
              </div>
            </div>
          </section>
        </main>

        <RankedResult
          key={`${state.online?.snapshot.code ?? 'none'}-${state.online?.snapshot.round ?? 0}`}
          blocked={Boolean(overlay)}
        />

        {overlay === 'leaderboard' && (
          <Dialog title="Рейтинг игроков" onClose={closeOverlay} wide>
            <Leaderboard />
          </Dialog>
        )}
        {overlay === 'levels' && (
          <Dialog title="Уровни" onClose={closeOverlay} wide>
            <Levels
              initialId={selectedLevel}
              onStart={(id) => {
                state.startLevel(id);
                setSelectedLevel(id);
                setOverlay(null);
              }}
            />
          </Dialog>
        )}
        {overlay === 'setup' && (
          <Dialog title="Новая игра" onClose={closeOverlay}>
            <Setup
              initialMode={setupMode}
              onQuickStart={beginQuick}
              onStart={() => {
                if (useGame.getState().mode === 'online') {
                  setOverlay(null);
                  return;
                }
                if (!settings.tutorialSeen) {
                  state.pause();
                  setAfterTutorial(true);
                  setOverlay('tutorial');
                } else setOverlay(null);
              }}
            />
          </Dialog>
        )}
        {overlay === 'settings' && (
          <Dialog title="Настройки" onClose={closeOverlay}>
            <Settings />
          </Dialog>
        )}
        {overlay === 'account' && (
          <Dialog title="Личный кабинет" onClose={closeOverlay} wide>
            {offline.online ? (
              <Account onOpenHistory={() => setOverlay('history')} />
            ) : (
              <p className={styles.muted}>
                {username ? `Офлайн-профиль: ${username}. ` : ''}Для входа, просмотра статистики и
                изменения аккаунта нужен интернет. Результаты уровней сохраняются на устройстве.
              </p>
            )}
          </Dialog>
        )}
        {overlay === 'quick' && (
          <Dialog title="Рейтинговая игра" onClose={closeOverlay}>
            <QuickMatch name={quickName} onCancel={closeOverlay} />
          </Dialog>
        )}
        {overlay === 'history' && (
          <Dialog title="История партий" onClose={closeOverlay}>
            <MatchHistory onOpen={() => setOverlay(null)} onSignIn={() => setOverlay('account')} />
          </Dialog>
        )}
        {overlay === 'tutorial' && (
          <Dialog
            title="Как играть"
            onClose={() => {
              settings.set('tutorialSeen', true);
              closeOverlay();
            }}
            wide
          >
            <Tutorial
              starting={afterTutorial}
              onDone={() => {
                settings.set('tutorialSeen', true);
                if (afterTutorial) state.resume();
                closeOverlay();
              }}
            />
          </Dialog>
        )}
        {overlay === 'online-pause' && pauseIdentity && (
          <Dialog
            title={state.online?.snapshot.pause?.endsAt ? 'Пауза · 2 минуты' : 'Запрос паузы'}
            onClose={closeOverlay}
          >
            <OnlinePause />
          </Dialog>
        )}
        {overlay === 'pause' && (
          <Dialog title="Пауза" onClose={closeOverlay}>
            <p className={styles.muted}>
              {state.mode === 'online'
                ? 'Онлайн-партия продолжается, пока открыто меню.'
                : 'Время остановлено.'}
            </p>
            <div className={styles.dialogActions}>
              {state.mode === 'online' && state.game.status === 'playing' && (
                <button
                  className={styles.primary}
                  disabled={
                    state.onlineStatus !== 'connected' ||
                    !state.online?.snapshot.players.every((p) => p?.connected) ||
                    Boolean(state.online?.snapshot.pause?.used && !pauseIdentity)
                  }
                  onClick={() =>
                    pauseIdentity ? setOverlay('online-pause') : state.requestOnlinePause()
                  }
                >
                  {state.online?.snapshot.pause?.used && !pauseIdentity
                    ? 'Пауза использована'
                    : pauseIdentity
                      ? 'Открыть паузу'
                      : 'Предложить паузу · 2 мин'}
                </button>
              )}
              <button className={styles.primary} onClick={closeOverlay}>
                Продолжить
                <ArrowRight size={19} />
              </button>
              {state.mode !== 'online' && (
                <button
                  className={styles.secondary}
                  onClick={() => {
                    if (state.game.history.length > 1) setOverlay('restart');
                    else {
                      state.restart();
                      setOverlay(null);
                    }
                  }}
                >
                  <RotateCcw size={18} /> Начать заново
                </button>
              )}
              <button className={styles.secondary} onClick={() => setOverlay('settings')}>
                <Settings2 size={18} /> Настройки
              </button>
              {level && (
                <button className={styles.secondary} onClick={openLevels}>
                  <Puzzle size={18} /> К уровням
                </button>
              )}
              <button className={styles.textButton} onClick={requestMenu}>
                <Home size={17} /> Главное меню
              </button>
            </div>
          </Dialog>
        )}
        {(overlay === 'leave' || overlay === 'restart') && (
          <Dialog
            title={overlay === 'leave' ? 'Завершить текущую партию?' : 'Начать партию заново?'}
            onClose={closeOverlay}
          >
            <p className={styles.muted}>
              {overlay === 'leave'
                ? 'Партия сохранится. Продолжить её можно из главного меню.'
                : 'Текущие ходы будут потеряны.'}
            </p>
            <div className={styles.dialogActions}>
              <button
                className={styles.primary}
                onClick={() => {
                  if (overlay === 'leave') state.menu();
                  else state.restart();
                  setOverlay(null);
                }}
              >
                {overlay === 'leave' ? 'Выйти в меню' : 'Начать заново'}
              </button>
              <button className={styles.secondary} onClick={closeOverlay}>
                Остаться в игре
              </button>
            </div>
          </Dialog>
        )}
        {overlay === 'leave-online' && (
          <Dialog title="Выйти из лобби?" onClose={closeOverlay}>
            <p className={styles.muted}>
              {state.online?.snapshot.ranking?.rated && state.game.status === 'playing'
                ? 'Выход засчитается как поражение и уменьшит рейтинг. При потере соединения у вас до 60 секунд на возврат; таймер хода продолжает идти.'
                : 'Лобби закроется для обоих игроков. При обычном обновлении страницы вы сможете вернуться в игру.'}
            </p>
            <div className={styles.dialogActions}>
              <button
                className={styles.primary}
                onClick={() => {
                  state.menu();
                  setOverlay(null);
                }}
              >
                Выйти из лобби
              </button>
              <button className={styles.secondary} onClick={closeOverlay}>
                Остаться в игре
              </button>
            </div>
          </Dialog>
        )}
      </div>
    </MotionConfig>
  );
}
