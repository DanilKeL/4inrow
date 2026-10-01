import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface Settings {
  sound: boolean;
  volume: number;
  setVolume: (value: number) => void;
  animations: boolean;
  hints: boolean;
  xrayDefault: boolean;
  tutorialSeen: boolean;
  set: (
    key: 'sound' | 'animations' | 'hints' | 'xrayDefault' | 'tutorialSeen',
    value: boolean,
  ) => void;
}
export const useSettings = create<Settings>()(
  persist(
    (set) => ({
      sound: true,
      volume: 1,
      setVolume: (value) =>
        set({ volume: Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 1 }),
      animations: !window.matchMedia('(prefers-reduced-motion: reduce)').matches,
      hints: true,
      xrayDefault: false,
      tutorialSeen: false,
      set: (key, value) => set({ [key]: value }),
    }),
    {
      name: 'four-cubed-settings',
      version: 1,
      merge: (persisted, current) => {
        const saved = (
          persisted && typeof persisted === 'object' ? persisted : {}
        ) as Partial<Settings>;
        const result = { ...current };
        for (const key of ['sound', 'animations', 'hints', 'xrayDefault', 'tutorialSeen'] as const)
          if (typeof saved[key] === 'boolean') result[key] = saved[key];
        if (typeof saved.volume === 'number' && Number.isFinite(saved.volume))
          result.volume = Math.max(0, Math.min(1, saved.volume));
        return result;
      },
    },
  ),
);
