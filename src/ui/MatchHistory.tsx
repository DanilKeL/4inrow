import { useEffect, useState } from 'react';
import { deserialize } from '../game/core';
import { useMatchHistory } from '../store/matchHistory';
import { useGame } from '../store/gameStore';
import { useAccount } from '../store/accountStore';
import styles from './Study.module.css';
import ui from './UI.module.css';

const labels = { local: 'Вдвоём', ai: 'Против AI', online: 'Онлайн' };
export function MatchHistory({ onOpen, onSignIn }: { onOpen: () => void; onSignIn: () => void }) {
  const { matches, statistics, rating, loading, error, refresh, rename, remove } =
    useMatchHistory();
  const username = useAccount((state) => state.username);
  useEffect(() => {
    if (username) void refresh();
  }, [username, refresh]);
  const [page, setPage] = useState(0);
  const [editing, setEditing] = useState<string | null>(null);
  const [title, setTitle] = useState('');
  const pages = Math.max(1, Math.ceil(matches.length / 2));
  const current = Math.min(page, pages - 1);
  if (!username)
    return (
      <>
        <p className={ui.muted}>
          Войдите в аккаунт, чтобы сохранять статистику и историю партий на сервере. Гостевые партии
          не учитываются.
        </p>
        <button className={ui.primary} onClick={onSignIn}>
          Войти или зарегистрироваться
        </button>
      </>
    );
  return (
    <>
      <p className={ui.muted}>
        Рейтинг: <strong data-testid="history-rating">{rating.points}</strong>. Последние 50 партий;
        статистика всех режимов.
      </p>
      <div className={styles.statistics} aria-label="Статистика аккаунта">
        {(
          [
            ['total', 'Партий'],
            ['wins', 'Побед'],
            ['losses', 'Поражений'],
            ['draws', 'Ничьих'],
          ] as const
        ).map(([key, label]) => (
          <div key={key}>
            <strong data-testid={`stats-${key}`}>{statistics[key]}</strong>
            <small>{label}</small>
          </div>
        ))}
      </div>
      {error && (
        <div>
          <p role="alert" className={ui.muted}>
            {error}
          </p>
          <button className={ui.secondary} disabled={loading} onClick={() => void refresh()}>
            Повторить
          </button>
        </div>
      )}
      {loading && (
        <p role="status" className={ui.muted}>
          Загружаем статистику…
        </p>
      )}
      {!matches.length && !loading && !error && (
        <p className={ui.muted}>Сыграйте партию до конца — она появится здесь автоматически.</p>
      )}
      <div className={styles.list}>
        {matches.slice(current * 2, current * 2 + 2).map((match) => {
          const game = deserialize(match.game);
          const winner = match.winner === undefined ? game.winner : match.winner;
          return (
            <article key={match.id} className={styles.entry}>
              {editing === match.id ? (
                <input
                  aria-label="Название партии"
                  autoFocus
                  maxLength={80}
                  value={title}
                  onChange={(event) => setTitle(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') {
                      void rename(match.id, title);
                      setEditing(null);
                    }
                  }}
                />
              ) : (
                <strong title={match.title}>{match.title}</strong>
              )}
              <small>
                {new Date(match.date).toLocaleDateString('ru-RU')} · {labels[match.mode]} ·{' '}
                {game.history.length} ходов
              </small>
              <small>
                {winner ? `Победа: ${match.names[winner - 1]}` : 'Ничья'}
                {match.ratingChange !== undefined &&
                  ` · ${match.ratingChange >= 0 ? '+' : ''}${match.ratingChange} Elo`}
                {match.endReason && ' · досрочно'}
              </small>
              <div className={styles.actions}>
                <button
                  disabled={loading}
                  onClick={() => {
                    useGame.getState().openArchive(match);
                    onOpen();
                  }}
                >
                  Смотреть
                </button>
                <button
                  disabled={loading}
                  onClick={() => {
                    if (editing === match.id) {
                      void rename(match.id, title);
                      setEditing(null);
                    } else {
                      setEditing(match.id);
                      setTitle(match.title);
                    }
                  }}
                >
                  {editing === match.id ? 'Сохранить' : 'Название'}
                </button>
                <button
                  aria-label={`Удалить партию ${match.title}`}
                  title="Убрать из истории; статистика сохранится"
                  disabled={loading}
                  onClick={() => void remove(match.id)}
                >
                  Удалить
                </button>
              </div>
            </article>
          );
        })}
      </div>
      {matches.length > 0 && (
        <div className={styles.paging}>
          <button disabled={current === 0} onClick={() => setPage(current - 1)}>
            Назад
          </button>
          <span>
            {current + 1} / {pages}
          </span>
          <button disabled={current + 1 === pages} onClick={() => setPage(current + 1)}>
            Дальше
          </button>
        </div>
      )}
    </>
  );
}
