import { useEffect, useState } from 'react';
import { Check, ChevronLeft, ChevronRight } from 'lucide-react';
import { LEVELS, moveLabel } from '../game/levels';
import { useLevelProgress } from '../store/levelStore';
import styles from './Levels.module.css';

export function Levels({
  onStart,
  initialId = 1,
}: {
  onStart: (id: number) => void;
  initialId?: number;
}) {
  const [page, setPage] = useState(Math.floor((initialId - 1) / 8));
  const best = useLevelProgress((state) => state.best);
  const progress = useLevelProgress();
  useEffect(() => {
    void useLevelProgress.getState().refresh();
  }, []);
  const shown = LEVELS.slice(page * 8, page * 8 + 8);
  return (
    <section className={styles.levels} data-testid="levels">
      <p className={styles.intro}>Победи из готовой позиции за меньшее число ходов.</p>
      <div className={styles.chapter}>
        <strong>{shown[0].chapter}</strong>
        <span>
          {Object.keys(best).length} / {LEVELS.length} пройдено
        </span>
      </div>
      <div className={styles.grid}>
        {shown.map((level) => (
          <button
            key={level.id}
            onClick={() => onStart(level.id)}
            aria-label={`Уровень ${level.id}`}
            className={best[level.id] ? styles.completed : ''}
          >
            <span className={styles.number}>
              {String(level.id).padStart(2, '0')}
              {best[level.id] && <Check size={15} aria-label="Пройден" />}
            </span>
            <small>{best[level.id] ? `Рекорд: ${moveLabel(best[level.id])}` : 'Рекорд: —'}</small>
          </button>
        ))}
      </div>
      <nav className={styles.pages} aria-label="Страницы уровней">
        <button
          disabled={page === 0}
          onClick={() => setPage(page - 1)}
          aria-label="Предыдущие уровни"
        >
          <ChevronLeft size={18} />
        </button>
        <span>
          {page + 1} / {Math.ceil(LEVELS.length / 8)}
        </span>
        <button
          disabled={(page + 1) * 8 >= LEVELS.length}
          onClick={() => setPage(page + 1)}
          aria-label="Следующие уровни"
        >
          <ChevronRight size={18} />
        </button>
      </nav>
      <small className={styles.note} role="status">
        {progress.owner
          ? progress.error ||
            (progress.loading ? 'Сохраняем прогресс…' : 'Прогресс сохранён в аккаунте.')
          : 'Войдите в аккаунт, чтобы сохранять прогресс на сервере.'}
      </small>
    </section>
  );
}
