import { useEffect, useState } from 'react';
import { useGame } from '../store/gameStore';
import { remainingTurnSeconds } from './turnTime';
import styles from './UI.module.css';

export function TurnTimer() {
  const snapshot = useGame((state) => state.online?.snapshot);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const remaining = remainingTurnSeconds(snapshot?.turnDeadline, snapshot?.pause?.endsAt, now);

  return (
    <span
      className={styles.turnTimer}
      data-testid="turn-timer"
      aria-hidden="true"
      title={remaining === null ? 'Ход без ограничения времени' : 'До конца хода'}
    >
      <strong>{remaining ?? '—'}</strong>
      <small>сек</small>
    </span>
  );
}
