import { useEffect, useState } from 'react';
import { RefreshCw, Trophy, CalendarDays } from 'lucide-react';
import { useDaily, isCurrentDaily } from '../store/dailyStore';
import { useAccount } from '../store/accountStore';
import { moveLabel } from '../game/levels';
import type { DailyChallenge as Challenge } from '../game/daily';
import styles from './DailyChallenge.module.css';
import ui from './UI.module.css';

export function DailyChallenge({
  onStart,
  results = false,
}: {
  onStart: (challenge: Challenge) => void;
  results?: boolean;
}) {
  const daily = useDaily();
  const username = useAccount((state) => state.username);
  const [tab, setTab] = useState<'challenge' | 'results'>(results ? 'results' : 'challenge');
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    void useDaily.getState().load();
    const timer = window.setInterval(() => {
      setNow(Date.now());
      if (!isCurrentDaily(useDaily.getState().challenge)) void useDaily.getState().load();
    }, 30000);
    return () => clearInterval(timer);
  }, []);
  const challenge = daily.challenge;
  const date = challenge
    ? new Date(`${challenge.date}T12:00:00+03:00`).toLocaleDateString('ru-RU', {
        day: 'numeric',
        month: 'long',
        timeZone: 'Europe/Moscow',
      })
    : '';
  const remaining = challenge
    ? Math.max(0, Math.floor((challenge.expiresAt - now - daily.serverOffset) / 60000))
    : 0;
  return (
    <section className={styles.root} data-testid="daily-challenge">
      <nav className={styles.tabs} aria-label="Задача дня">
        <button aria-pressed={tab === 'challenge'} onClick={() => setTab('challenge')}>
          Задача
        </button>
        <button aria-pressed={tab === 'results'} onClick={() => setTab('results')}>
          Результаты
        </button>
      </nav>
      {daily.loading && !challenge ? (
        <p role="status">Загрузка…</p>
      ) : daily.error ? (
        <div role="alert" className={styles.error}>
          <p>{daily.error}</p>
          <button className={ui.secondary} onClick={() => void daily.load()}>
            Повторить
          </button>
        </div>
      ) : (
        challenge && (
          <>
            <div className={styles.heading}>
              <span>
                <CalendarDays size={17} />
                {date}
              </span>
              <small>
                До смены {Math.floor(remaining / 60)} ч {remaining % 60} мин
              </small>
            </div>
            {tab === 'challenge' ? (
              <>
                <div className={styles.goal}>Победить за минимум ходов</div>
                <div className={styles.record}>
                  <span>Ваш рекорд</span>
                  <strong>{daily.ownBest === null ? '—' : moveLabel(daily.ownBest)}</strong>
                </div>
                <button
                  className={ui.primary}
                  disabled={daily.loading || !isCurrentDaily(challenge)}
                  onClick={() => onStart(challenge)}
                >
                  Играть
                </button>
              </>
            ) : (
              <>
                <div className={styles.summary}>
                  <span>
                    <Trophy size={17} />
                    Результаты дня
                  </span>
                  <button
                    aria-label="Обновить результаты дня"
                    onClick={() => void daily.load()}
                    disabled={daily.loading}
                  >
                    <RefreshCw size={16} />
                  </button>
                </div>
                {daily.leaderboard.length === 0 ? (
                  <p className={styles.empty}>Результатов пока нет</p>
                ) : (
                  <div
                    className={styles.scroll}
                    data-testid="daily-leaderboard"
                    tabIndex={0}
                    aria-label="Результаты дня"
                  >
                    <table>
                      <thead>
                        <tr>
                          <th scope="col">Место</th>
                          <th scope="col">Игрок</th>
                          <th scope="col">Ходы</th>
                        </tr>
                      </thead>
                      <tbody>
                        {daily.leaderboard.map((player) => (
                          <tr
                            key={player.username}
                            className={player.username === username ? styles.self : ''}
                          >
                            <td>{player.rank}</td>
                            <th scope="row">{player.username}</th>
                            <td>{player.moves}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </>
            )}
          </>
        )
      )}
    </section>
  );
}
