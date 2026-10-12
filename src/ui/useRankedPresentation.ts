import { useEffect, useState } from 'react';

export function useResultReveal(key: string | null, delay: number, ready: boolean) {
  const [revealedKey, setRevealedKey] = useState<string | null>(null);
  useEffect(() => {
    if (!key || !ready) return;
    let remaining = delay;
    let started: number | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const update = () => {
      clearTimeout(timer);
      if (started !== null) remaining = Math.max(0, remaining - (performance.now() - started));
      started = null;
      if (document.visibilityState === 'hidden') return;
      started = performance.now();
      timer = setTimeout(() => setRevealedKey(key), remaining);
    };
    update();
    document.addEventListener('visibilitychange', update);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', update);
    };
  }, [key, delay, ready]);
  return ready && key !== null && revealedKey === key;
}

export function useAnimatedInteger(
  target: number,
  from: number,
  enabled: boolean,
  reducedMotion: boolean,
  delay = 0,
) {
  const [value, setValue] = useState(from);
  useEffect(() => {
    if (!enabled) {
      setValue(from);
      return;
    }
    if (reducedMotion) {
      setValue(target);
      return;
    }
    let frame = 0;
    const started = performance.now() + delay;
    const update = (now: number) => {
      const progress = Math.max(0, Math.min(1, (now - started) / 850));
      const eased = 1 - (1 - progress) ** 3;
      setValue(Math.round(from + (target - from) * eased));
      if (progress < 1) frame = requestAnimationFrame(update);
    };
    frame = requestAnimationFrame(update);
    return () => cancelAnimationFrame(frame);
  }, [delay, enabled, from, reducedMotion, target]);
  return value;
}
