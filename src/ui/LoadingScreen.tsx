import { useEffect, useState } from 'react';
import styles from './LoadingScreen.module.css';

export function LoadingScreen({
  ready,
  failed,
  mediaProgress,
  onSkipVideos,
}: {
  ready: boolean;
  failed: boolean;
  mediaProgress?: string;
  onSkipVideos?: () => void;
}) {
  const [dismissed, setDismissed] = useState(false);
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setSlow(true), 8000);
    return () => clearTimeout(timer);
  }, []);
  useEffect(() => {
    if (!ready || failed) return;
    const timer = setTimeout(() => setDismissed(true), 450);
    return () => clearTimeout(timer);
  }, [ready, failed]);
  if (dismissed && !failed) return null;
  return (
    <div
      className={`${styles.screen} ${ready && !failed ? styles.leaving : ''}`}
      data-testid="loading-screen"
      role={failed ? 'alert' : 'status'}
      aria-live="polite"
    >
      <div className={styles.content}>
        <div className={styles.brand}>
          FOUR<sup>3</sup>
        </div>
        <div className={styles.sculpture} aria-hidden="true">
          <i className={styles.base} />
          <i className={styles.coin} />
          <i className={styles.coin} />
          <i className={styles.coin} />
        </div>
        <h1>{failed ? 'Не удалось загрузить поле' : 'Загрузка игры'}</h1>
        <p>
          {failed
            ? 'Проверьте соединение и попробуйте ещё раз.'
            : ready
              ? 'Готово'
              : mediaProgress
                ? `Видео с правилами · ${mediaProgress}`
                : 'Доска и фишки…'}
        </p>
        {failed ? (
          <button onClick={() => window.location.reload()}>Попробовать снова</button>
        ) : (
          <div className={styles.track} aria-hidden="true">
            <i />
          </div>
        )}
        {!failed && !ready && slow && mediaProgress && (
          <button onClick={onSkipVideos}>Продолжить без ожидания видео</button>
        )}
      </div>
    </div>
  );
}
