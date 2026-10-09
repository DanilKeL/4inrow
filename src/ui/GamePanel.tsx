import {
  ChevronFirst,
  ChevronLast,
  ChevronLeft,
  ChevronRight,
  RotateCcw,
  Trophy,
  Play,
} from 'lucide-react';
import { useGame } from '../store/gameStore';
import styles from './UI.module.css';
import { getLevel, LEVELS, levelMoveCount, moveLabel } from '../game/levels';
import { useLevelProgress } from '../store/levelStore';
import { useDaily } from '../store/dailyStore';
import { dailyMoveCount } from '../game/daily';

export function timeLabel(seconds: number) {
  return `${Math.floor(seconds / 60)
    .toString()
    .padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`;
}

export function GamePanel({
  onMenu,
  onLevels,
  onDailyResults,
}: {
  onMenu: () => void;
  onLevels: () => void;
  onDailyResults: () => void;
}) {
  const state = useGame();
  const { game, phase } = state;
  const finished = game.status !== 'playing';
  const level = getLevel(state.levelId);
  const daily = useDaily();
  const challenge = state.mode === 'daily' ? state.dailyChallenge : null;
  const best = useLevelProgress((s) => (level ? s.best[level.id] : undefined));
  const moves = challenge
    ? dailyMoveCount(game, challenge)
    : level
      ? levelMoveCount(game, level)
      : 0;
  const result = daily.result?.id === state.recordId ? daily.result : null;
  return (
    <aside className={styles.gamePanel}>
      <div className={styles.panelEyebrow}>
        {challenge
          ? 'ЗАДАЧА ДНЯ'
          : level
            ? `УРОВЕНЬ ${level.id} / ${LEVELS.length}`
            : state.mode === 'ai'
              ? 'ПРОТИВ AI'
              : state.mode === 'online'
                ? 'ОНЛАЙН'
                : 'ВДВОЁМ'}
      </div>
      {phase === 'replay' ? (
        <>
          <h2>Повтор партии</h2>
        </>
      ) : finished ? (
        <>
          <Trophy size={30} className={styles.trophy} />
          <h2>
            {challenge
              ? game.winner === 1
                ? 'Задача решена'
                : game.status === 'draw'
                  ? 'Ничья'
                  : 'Поражение'
              : level
                ? game.winner === 1
                  ? 'Уровень пройден'
                  : game.status === 'draw'
                    ? 'Ничья'
                    : 'Поражение'
                : game.status === 'won'
                  ? `Победа: ${state.names[game.winner! - 1]}`
                  : 'Ничья'}
          </h2>
          {level && game.winner === 1 && (
            <p className={`${styles.muted} ${styles.levelResult}`} data-testid="level-result">
              {state.levelBestBefore === null || moves < state.levelBestBefore
                ? 'Новый рекорд'
                : 'Победа'}{' '}
              · {moveLabel(moves)}
            </p>
          )}
          {challenge && game.winner === 1 && (
            <div className={`${styles.muted} ${styles.levelResult}`} data-testid="daily-result">
              {moveLabel(moves)} ·{' '}
              {result?.status === 'verified'
                ? 'Результат подтверждён'
                : result?.status === 'guest'
                  ? 'Для таблицы результатов нужен аккаунт.'
                  : result?.status === 'failed'
                    ? result.error
                    : 'Проверяем результат…'}
              {result?.status === 'failed' &&
                daily.pending.some((item) => item.id === state.recordId) && (
                  <button className={styles.textButton} onClick={() => void daily.flush()}>
                    Повторить отправку
                  </button>
                )}
            </div>
          )}
          {state.online?.snapshot.endReason && (
            <p className={styles.muted}>{state.online.snapshot.endReason}</p>
          )}
        </>
      ) : (
        <>
          <h2>{challenge ? 'Задача дня' : level ? level.chapter : 'Текущая партия'}</h2>
        </>
      )}
      <div className={styles.players}>
        {([1, 2] as const).map((player) => (
          <div
            key={player}
            className={`${styles.player} ${game.currentPlayer === player && !finished ? styles.activePlayer : ''}`}
          >
            <span className={`${styles.token} ${player === 2 ? styles.ivory : ''}`}>
              {player === 1 ? '●' : '○'}
            </span>
            <span>
              <strong>{state.names[player - 1]}</strong>
              <small>{player === 1 ? 'Графит · ●' : 'Слоновая кость · ○'}</small>
            </span>
            {game.currentPlayer === player && !finished && <span className={styles.activeDot} />}
          </div>
        ))}
      </div>
      <div className={styles.stats}>
        <div>
          <small>{level || challenge ? 'ВАШИ ХОДЫ' : 'ХОДЫ'}</small>
          <strong data-testid="move-count">
            {level || challenge
              ? moves
              : phase === 'replay'
                ? state.replayIndex
                : game.history.length}
            {!level && !challenge && <span> / 125</span>}
          </strong>
        </div>
        <div>
          <small>{level || challenge ? 'ЛИЧНЫЙ РЕКОРД' : 'ВРЕМЯ'}</small>
          <strong>
            {challenge
              ? daily.challenge?.id === challenge.id
                ? (daily.ownBest ?? '—')
                : '—'
              : level
                ? (best ?? '—')
                : timeLabel(state.elapsed)}
          </strong>
        </div>
      </div>
      {phase === 'replay' ? (
        <>
          <div className={styles.replayControls}>
            <button
              aria-label="В начало повтора"
              onClick={() => state.seek(0)}
              disabled={state.replayIndex === 0}
            >
              <ChevronFirst />
            </button>
            <button
              aria-label="Предыдущий ход"
              onClick={() => state.seek(state.replayIndex - 1)}
              disabled={state.replayIndex === 0}
            >
              <ChevronLeft />
            </button>
            <button
              aria-label="Следующий ход"
              onClick={() => state.seek(state.replayIndex + 1)}
              disabled={state.replayIndex === game.history.length}
            >
              <ChevronRight />
            </button>
            <button
              aria-label="В конец повтора"
              onClick={() => state.seek(game.history.length)}
              disabled={state.replayIndex === game.history.length}
            >
              <ChevronLast />
            </button>
          </div>
          <p className={styles.replayLabel}>
            Ход {state.replayIndex} из {game.history.length}
          </p>
          <button className={styles.secondary} onClick={state.closeReplay}>
            Завершить просмотр
          </button>
        </>
      ) : finished && challenge ? (
        <>
          <button className={styles.primary} onClick={state.restart}>
            <RotateCcw size={17} /> Повторить задачу
          </button>
          <button className={styles.secondary} onClick={onDailyResults}>
            <Trophy size={17} /> Результаты дня
          </button>
          <button className={styles.textButton} onClick={onMenu}>
            Главное меню
          </button>
        </>
      ) : finished && level ? (
        <>
          {game.winner === 1 && level.id < LEVELS.length && (
            <button className={styles.primary} onClick={() => state.startLevel(level.id + 1)}>
              Следующий уровень <ChevronRight size={18} />
            </button>
          )}
          <button
            className={
              game.winner === 1 && level.id < LEVELS.length ? styles.secondary : styles.primary
            }
            onClick={state.restart}
          >
            <RotateCcw size={17} /> Повторить уровень
          </button>
          <button className={styles.textButton} onClick={onLevels}>
            К уровням
          </button>
        </>
      ) : finished ? (
        <>
          <button
            className={styles.primary}
            onClick={state.restart}
            disabled={
              state.mode === 'online' &&
              (state.onlineStatus !== 'connected' ||
                state.online?.snapshot.rematch.includes(state.online.player))
            }
          >
            <RotateCcw size={18} />{' '}
            {state.mode === 'online' && state.online?.snapshot.rematch.includes(state.online.player)
              ? 'Ждём согласия соперника'
              : 'Ещё партия'}
          </button>
          <button className={styles.secondary} onClick={state.openReplay}>
            <Play size={17} /> Повтор партии
          </button>
          <button className={styles.textButton} onClick={onMenu}>
            Главное меню
          </button>
        </>
      ) : null}
    </aside>
  );
}
