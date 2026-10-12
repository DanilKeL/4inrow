import { useEffect, useState } from 'react';

// Mobile browsers can discard a hidden page. Keep navigation, never form fields
// or credentials, in this tab's session so returning restores the same screen.
export function useBackgroundState<T>(
  key: string,
  fallback: T,
  accepts: (value: unknown) => value is T,
  restore = true,
) {
  const [value, setValue] = useState<T>(() => {
    try {
      const stored: unknown = JSON.parse(sessionStorage.getItem(key) ?? 'null');
      if (restore && accepts(stored)) return stored;
    } catch {
      // Storage may be unavailable in private browsing.
    }
    return fallback;
  });
  useEffect(() => {
    const clear = () => {
      try {
        sessionStorage.removeItem(key);
      } catch {
        // Navigation also works without storage.
      }
    };
    const save = () => {
      try {
        sessionStorage.setItem(key, JSON.stringify(value));
      } catch {
        // The current page keeps its state even if storage is unavailable.
      }
    };
    const visibility = () => {
      if (document.hidden) save();
      else clear();
    };
    visibility();
    document.addEventListener('visibilitychange', visibility);
    window.addEventListener('pagehide', save);
    window.addEventListener('pageshow', clear);
    return () => {
      document.removeEventListener('visibilitychange', visibility);
      window.removeEventListener('pagehide', save);
      window.removeEventListener('pageshow', clear);
    };
  }, [key, value]);
  return [value, setValue] as const;
}
