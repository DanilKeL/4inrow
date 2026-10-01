import { useEffect, useState } from 'react';
import { ArrowRight, Search, UsersRound } from 'lucide-react';
import { useGame } from '../store/gameStore';
import { useAccount } from '../store/accountStore';
import styles from './UI.module.css';

export function QuickMatch({ name, onCancel }: { name: string; onCancel: () => void }) {
  const { quickMatch, onlineStatus, onlineError, acceptQuickMatch, findQuickMatch } = useGame();
  const [now, setNow] = useState(Date.now());
  const username = useAccount((s) => s.username);
  useEffect(() => {
    if (quickMatch?.status !== 'found') return;
    const timer = window.setInterval(() => setNow(Date.now()), 200);
    return () => window.clearInterval(timer);
  }, [quickMatch?.status]);
  const seconds =
    quickMatch?.status === 'found' ? Math.max(0, Math.ceil((quickMatch.deadline - now) / 1000)) : 0;
  return (
    <div className={styles.quickMatch}>
      {quickMatch?.status === 'found' ? (
        <>
          <UsersRound size={32} aria-hidden="true" />
          <strong>Соперник найден: {quickMatch.opponent}</strong>
          <small>
            {quickMatch.opponentRating !== undefined
              ? `Рейтинг соперника: ${quickMatch.opponentRating} · ${quickMatch.rated ? 'На рейтинг' : 'Без очков: лимит встреч'}`
              : 'Гостевая игра без рейтинга'}
          </small>
          <p className={styles.muted}>
            Подтвердите игру за {seconds} сек. Матч начнётся, когда согласитесь оба.
            {quickMatch.rated && ' На ход — 90 сек. Выход — поражение.'}
          </p>
          <button
            className={styles.primary}
            disabled={quickMatch.accepted || seconds === 0 || onlineStatus !== 'connected'}
            onClick={acceptQuickMatch}
          >
            {quickMatch.accepted ? 'Ждём подтверждения соперника…' : 'Принять матч'}
            {!quickMatch.accepted && <ArrowRight size={18} />}
          </button>
          <button className={styles.secondary} onClick={onCancel}>
            Отказаться
          </button>
        </>
      ) : onlineStatus === 'error' ? (
        <>
          <p role="alert" className={styles.onlineError}>
            {onlineError || 'Не удалось найти игру.'}
          </p>
          <button className={styles.primary} onClick={() => findQuickMatch(name)}>
            Искать снова <ArrowRight size={18} />
          </button>
          <button className={styles.secondary} onClick={onCancel}>
            В главное меню
          </button>
        </>
      ) : (
        <>
          <Search size={32} aria-hidden="true" />
          <strong>
            {onlineStatus === 'reconnecting' ? 'Восстанавливаем поиск…' : 'Ищем соперника…'}
          </strong>
          <p className={styles.muted}>
            {onlineStatus === 'reconnecting' ? (
              'Соединение прервалось. Поиск продолжится автоматически после подключения.'
            ) : (
              <>
                {username
                  ? 'Рейтинговый поиск среди аккаунтов.'
                  : 'Поиск среди гостей, без рейтинга.'}{' '}
                На подтверждение — 15 секунд.
              </>
            )}
          </p>
          <button className={styles.secondary} onClick={onCancel}>
            Отменить поиск
          </button>
        </>
      )}
    </div>
  );
}
