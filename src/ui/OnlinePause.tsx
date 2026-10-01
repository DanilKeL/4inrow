import { useEffect, useState } from 'react';
import { useGame } from '../store/gameStore';
import { timeLabel } from './GamePanel';
import styles from './UI.module.css';

export function OnlinePause() {
  const { online, onlineStatus, answerOnlinePause, readyOnlinePause } = useGame();
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(timer);
  }, []);
  const pause = online?.snapshot.pause;
  const request = pause?.request;
  const mineReady = Boolean(online && pause?.ready?.includes(online.player));
  const peerReady = Boolean(online && pause?.ready?.includes(online.player === 1 ? 2 : 1));
  const remaining = Math.max(
    0,
    Math.min(
      pause?.endsAt ? 120 : 30,
      Math.ceil(((pause?.endsAt ?? request?.expiresAt ?? now) - now) / 1000),
    ),
  );
  if (pause?.endsAt)
    return (
      <div className={styles.onlinePause}>
        <strong className={styles.pauseCountdown} data-testid="pause-countdown">
          {timeLabel(remaining)}
        </strong>
        <p className={styles.muted}>
          {remaining
            ? 'Оба готовы — продолжаем сразу. Иначе ждём окончания таймера.'
            : 'Ждём продолжения партии…'}
        </p>
        <button
          className={styles.primary}
          onClick={readyOnlinePause}
          disabled={
            mineReady ||
            !remaining ||
            onlineStatus !== 'connected' ||
            !online?.snapshot.players.every((p) => p?.connected)
          }
        >
          {mineReady ? 'Вы готовы' : 'Готов'}
        </button>
        <p className={styles.muted} role="status">
          {mineReady ? 'Ждём готовности соперника.' : peerReady ? 'Соперник готов.' : ''}
        </p>
        {onlineStatus !== 'connected' && <p role="status">Восстанавливаем соединение…</p>}
      </div>
    );
  if (!request || !online) return null;
  const own = request.by === online.player;
  return (
    <>
      <p className={styles.muted}>
        {own
          ? 'Ждём согласия соперника.'
          : `${online.snapshot.players[request.by - 1]?.name} предлагает паузу на 2 минуты.`}
      </p>
      <p className={styles.muted}>На ответ: {remaining} сек. До принятия партия продолжается.</p>
      <div className={styles.dialogActions}>
        {!own && (
          <button
            className={styles.primary}
            disabled={onlineStatus !== 'connected' || !remaining}
            onClick={() => answerOnlinePause(true)}
          >
            Принять паузу
          </button>
        )}
        <button
          className={styles.secondary}
          disabled={onlineStatus !== 'connected'}
          onClick={() => answerOnlinePause(false)}
        >
          {own ? 'Отменить запрос' : 'Отклонить'}
        </button>
      </div>
    </>
  );
}
