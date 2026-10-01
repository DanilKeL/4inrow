import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { ArrowRight, Pause, Play, RotateCcw } from 'lucide-react';
import { useReducedMotion } from 'motion/react';
import { useSettings } from '../store/settingsStore';
import { tutorialExamples } from './tutorialExamples';
import { tutorialVideoUrl } from '../network/tutorialMedia';
import styles from './Tutorial.module.css';
import ui from './UI.module.css';

function LessonVideo({ id, title, autoPlay }: { id: string; title: string; autoPlay: boolean }) {
  const ref = useRef<HTMLVideoElement>(null);
  const [source] = useState(() => tutorialVideoUrl(id));
  const [playing, setPlaying] = useState(false);
  const [ended, setEnded] = useState(false);
  const [failed, setFailed] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const frame = useRef<number | null>(null);
  const syncProgress = () => {
    const video = ref.current;
    if (!video) return;
    const nextDuration = Number.isFinite(video.duration) && video.duration > 0 ? video.duration : 0;
    if (nextDuration) setDuration(nextDuration);
    setTime(nextDuration ? Math.min(video.currentTime, nextDuration) : 0);
  };
  const stopProgress = () => {
    if (frame.current !== null) cancelAnimationFrame(frame.current);
    frame.current = null;
  };
  const animateProgress = () => {
    stopProgress();
    const update = () => {
      syncProgress();
      const video = ref.current;
      if (video && !video.paused && !video.ended) frame.current = requestAnimationFrame(update);
      else frame.current = null;
    };
    frame.current = requestAnimationFrame(update);
  };
  useEffect(() => {
    const video = ref.current;
    if (autoPlay) void video?.play().catch(() => setPlaying(false));
    const stopInBackground = () => {
      if (document.hidden) video?.pause();
    };
    document.addEventListener('visibilitychange', stopInBackground);
    return () => {
      stopProgress();
      video?.pause();
      document.removeEventListener('visibilitychange', stopInBackground);
    };
  }, [autoPlay]);
  function play(fromStart = false) {
    const video = ref.current;
    if (!video) return;
    if (fromStart || video.ended) video.currentTime = 0;
    void video.play().catch(() => setPlaying(false));
  }
  const progress = duration > 0 ? Math.max(0, Math.min(100, (time / duration) * 100)) : 0;
  return (
    <div className={styles.media}>
      {failed ? (
        <img src={`/tutorial/${id}.webp`} alt={title} />
      ) : (
        <video
          ref={ref}
          src={source}
          poster={`/tutorial/${id}.webp`}
          aria-label={`Пример: ${title}`}
          autoPlay={autoPlay}
          muted
          playsInline
          preload={autoPlay ? 'auto' : 'none'}
          onPlay={() => {
            setPlaying(true);
            setEnded(false);
            animateProgress();
          }}
          onPause={() => {
            stopProgress();
            syncProgress();
            setPlaying(false);
          }}
          onEnded={() => {
            stopProgress();
            syncProgress();
            setPlaying(false);
            setEnded(true);
          }}
          onError={() => setFailed(true)}
          onLoadedMetadata={syncProgress}
          onDurationChange={syncProgress}
          onSeeked={syncProgress}
        />
      )}
      {ended && id !== 'stacking' && <span className={styles.winner}>4 в ряд — победа</span>}
      {failed ? (
        <p className={styles.mediaFallback}>Видео недоступно. Показан итоговый пример.</p>
      ) : (
        <div className={styles.playback}>
          <button
            aria-label={playing ? 'Остановить пример' : 'Воспроизвести пример'}
            onClick={() => (playing ? ref.current?.pause() : play())}
          >
            {playing ? <Pause size={16} /> : <Play size={16} />}
          </button>
          <input
            type="range"
            aria-label="Позиция ролика"
            min={0}
            max={duration || 1}
            step={0.05}
            value={Math.min(time, duration || 1)}
            disabled={!duration}
            style={{ '--video-progress': `${progress}%` } as CSSProperties}
            onChange={(e) => {
              if (ref.current) {
                ref.current.currentTime = Number(e.target.value);
                setTime(Number(e.target.value));
              }
            }}
          />
          <button aria-label="Повторить пример" onClick={() => play(true)}>
            <RotateCcw size={16} />
          </button>
        </div>
      )}
    </div>
  );
}

export function Tutorial({ onDone, starting = false }: { onDone: () => void; starting?: boolean }) {
  const [selected, setSelected] = useState(0);
  const reducedMotion = useReducedMotion();
  const animations = useSettings((state) => state.animations);
  const example = tutorialExamples[selected];
  return (
    <div className={styles.guide} data-guide>
      <p className={styles.goal}>
        Соберите <strong>4 фишки своего цвета</strong> по прямой, без пропусков.
      </p>
      <nav className={styles.examples} aria-label="Примеры правил">
        {tutorialExamples.map((item, index) => (
          <button
            key={item.id}
            aria-pressed={selected === index}
            onClick={() => setSelected(index)}
          >
            <span>{String(index + 1).padStart(2, '0')}</span>
            {item.tab}
          </button>
        ))}
      </nav>
      <section className={styles.lesson} aria-labelledby="lesson-title">
        <LessonVideo
          key={example.id}
          id={example.id}
          title={example.title}
          autoPlay={animations && !reducedMotion}
        />
        <div className={styles.caption} aria-live="polite">
          <h3 id="lesson-title">{example.title}</h3>
          <p>{example.description}</p>
        </div>
      </section>
      <div className={styles.footer}>
        <button
          className={styles.next}
          onClick={() => setSelected((selected + 1) % tutorialExamples.length)}
        >
          {selected === tutorialExamples.length - 1 ? 'К первому примеру' : 'Следующий пример'}
          <ArrowRight size={16} />
        </button>
        <button className={ui.primary} onClick={onDone}>
          {starting ? 'Начать' : 'Понятно'}
        </button>
      </div>
    </div>
  );
}
