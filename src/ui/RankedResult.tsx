import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { Clock3, Eye, Home, RotateCcw, TrendingDown, TrendingUp } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { useGame } from '../store/gameStore';
import styles from './RankedResult.module.css';

function useAnimatedInteger(target: number, delay = 0) {
  const reducedMotion = useReducedMotion();
  const [value, setValue] = useState(reducedMotion ? target : 0);
  useEffect(() => {
    if (reducedMotion) {
      setValue(target);
      return;
    }
    let frame = 0;
    const started = performance.now() + delay;
    const update = (now: number) => {
      if (now < started) {
        frame = requestAnimationFrame(update);
        return;
      }
      const progress = Math.min(1, (now - started) / 850);
      const eased = 1 - (1 - progress) ** 3;
      setValue(Math.round(target * eased));
      if (progress < 1) frame = requestAnimationFrame(update);
    };
    frame = requestAnimationFrame(update);
    return () => cancelAnimationFrame(frame);
  }, [delay, reducedMotion, target]);
  return value;
}

export function RankedResult({ blocked = false }: { blocked?: boolean }) {
  const state = useGame();
  const [dismissed, setDismissed] = useState(false);
  const panel = useRef<HTMLDivElement>(null);
  const snapshot = state.online?.snapshot;
  const ranking = snapshot?.ranking;
  const index = (state.online?.player ?? 1) - 1;
  const delta = ranking?.changes?.[index] ?? 0;
  const animatedDelta = useAnimatedInteger(delta, 220);
  const animatedRating = useAnimatedInteger((ranking?.points[index] ?? 0) + delta, 80);
  const visible = Boolean(
    !blocked &&
    !dismissed &&
    state.mode === 'online' &&
    snapshot &&
    snapshot.game.status !== 'playing' &&
    ranking?.rated &&
    ranking.changes,
  );

  useEffect(() => {
    if (!visible) return;
    panel.current?.focus({ preventScroll: true });
    const close = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setDismissed(true);
    };
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, [visible]);

  if (!visible || !snapshot || !ranking || !state.online) return null;
  const player = state.online.player;
  const winner = snapshot.game.winner;
  const won = winner === player;
  const lost = winner !== null && winner !== player;
  const opponent = snapshot.players[player === 1 ? 1 : 0]?.name ?? 'соперником';
  const waiting = snapshot.rematch.includes(player);
  const connected = snapshot.players.every((seat) => seat?.connected);
  const resultTitle = won ? 'Победа' : lost ? 'Поражение' : 'Ничья';
  const resultText = won
    ? `Вы обыграли ${opponent}`
    : lost
      ? `${opponent} выиграл эту партию`
      : `Равная партия с ${opponent}`;

  return (
    <div className={styles.backdrop} data-testid="ranked-result-backdrop">
      <motion.div
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-labelledby="ranked-result-title"
        tabIndex={-1}
        className={`${styles.panel} ${won ? styles.won : lost ? styles.lost : styles.draw}`}
        initial={{ opacity: 0, scale: 0.96, y: 18 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        transition={{ type: 'spring', stiffness: 250, damping: 24 }}
        data-testid="ranked-result"
      >
        {won && (
          <div className={styles.particles} aria-hidden="true">
            {Array.from({ length: 12 }, (_, index) => (
              <span
                key={index}
                style={
                  {
                    '--particle-index': index,
                    '--particle-x': `${((index * 37) % 100) - 50}px`,
                  } as CSSProperties
                }
              />
            ))}
          </div>
        )}
        <p className={styles.eyebrow}>РЕЙТИНГОВАЯ ПАРТИЯ ЗАВЕРШЕНА</p>
        <motion.div
          className={styles.resultMark}
          initial={{ scale: 0.6, rotate: -8 }}
          animate={{ scale: 1, rotate: 0 }}
          transition={{ type: 'spring', stiffness: 260, damping: 18, delay: 0.08 }}
        >
          {delta >= 0 ? <TrendingUp size={30} /> : <TrendingDown size={30} />}
        </motion.div>
        <h2 id="ranked-result-title">{resultTitle}</h2>
        <p className={styles.resultText}>{resultText}</p>
        {snapshot.endReason && <p className={styles.endReason}>{snapshot.endReason}</p>}

        <div className={styles.ratingCard}>
          <span>Изменение Elo</span>
          <strong
            className={delta >= 0 ? styles.positive : styles.negative}
            data-testid="ranked-result-delta"
          >
            {animatedDelta >= 0 ? '+' : ''}
            {animatedDelta}
          </strong>
          <div>
            <span>{ranking.points[index]}</span>
            <i aria-hidden="true">→</i>
            <b data-testid="ranked-result-rating">{animatedRating}</b>
          </div>
        </div>

        <div className={styles.actions}>
          <button
            className={styles.rematch}
            disabled={waiting || !connected || state.onlineStatus !== 'connected'}
            onClick={state.restart}
          >
            {waiting ? <Clock3 size={18} /> : <RotateCcw size={18} />}
            {waiting
              ? 'Ждём решения соперника'
              : connected
                ? `Сыграть ещё с ${opponent}`
                : 'Соперник не в сети'}
          </button>
          <small>Реванш не влияет на рейтинг</small>
          <button className={styles.secondary} onClick={() => setDismissed(true)}>
            <Eye size={17} /> Посмотреть поле
          </button>
          <button className={styles.menu} onClick={state.menu}>
            <Home size={16} /> Главное меню
          </button>
        </div>
      </motion.div>
    </div>
  );
}
