import { useEffect, useState } from 'react';
import { RefreshCw, Trophy } from 'lucide-react';
import type { LeaderboardResponse } from '../network/leaderboard';
import { useAccount } from '../store/accountStore';
import styles from './Leaderboard.module.css';

export function Leaderboard() {
  const username = useAccount((state) => state.username);
  const [data, setData] = useState<LeaderboardResponse | null>(null);
  const [error, setError] = useState(false);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true;
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 12_000);
    setData(null);
    setError(false);
    void fetch('/auth/leaderboard', { signal: controller.signal, cache: 'no-store' })
      .then(async (response) => {
        if (!response.ok) throw new Error('Leaderboard unavailable');
        const result = (await response.json()) as LeaderboardResponse;
        if (active) setData(result);
      })
      .catch(() => {
        if (active) setError(true);
      })
      .finally(() => window.clearTimeout(timeout));
    return () => {
      active = false;
      window.clearTimeout(timeout);
      controller.abort();
    };
  }, [revision]);

  return (
    <div className={styles.root}>
      <div className={styles.summary}>
        <span>
          <Trophy size={18} /> Топ 100 · Elo
        </span>
        <button aria-label="Обновить рейтинг" onClick={() => setRevision((value) => value + 1)}>
          <RefreshCw size={16} />
        </button>
      </div>
      {error ? (
        <div className={styles.state} role="alert">
          <p>Не удалось загрузить рейтинг.</p>
          <button onClick={() => setRevision((value) => value + 1)}>Попробовать снова</button>
        </div>
      ) : !data ? (
        <p className={styles.state} role="status">
          Загрузка рейтинга…
        </p>
      ) : data.players.length === 0 ? (
        <p className={styles.state}>В рейтинге пока нет игроков.</p>
      ) : (
        <div className={styles.scroll} tabIndex={0} aria-label="Список игроков">
          <table className={styles.table}>
            <caption>Игроки по рейтингу Elo. Игры — рейтинговые партии.</caption>
            <thead>
              <tr>
                <th scope="col">Место</th>
                <th scope="col">Игрок</th>
                <th scope="col">Elo</th>
                <th scope="col">Игры</th>
              </tr>
            </thead>
            <tbody>
              {data.players.map((player) => (
                <tr
                  key={player.username}
                  className={player.username === username ? styles.self : undefined}
                >
                  <td>
                    <span className={player.rank <= 3 ? styles.medal : styles.rank}>
                      {player.rank}
                    </span>
                  </td>
                  <th scope="row">
                    <span className={styles.name}>{player.username}</span>
                    {player.username === username && <small>Вы</small>}
                  </th>
                  <td className={styles.elo}>{player.elo.toLocaleString('ru-RU')}</td>
                  <td>{player.games.toLocaleString('ru-RU')}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
