// @vitest-environment jsdom
import { afterAll, expect, it, vi } from 'vitest';

vi.stubGlobal('matchMedia', () => ({ matches: false }));
const { useSettings } = await import('../store/settingsStore');
const parameter = () => ({
  setValueAtTime: vi.fn(),
  linearRampToValueAtTime: vi.fn(),
  exponentialRampToValueAtTime: vi.fn(),
});
const gains: Array<{ gain: ReturnType<typeof parameter>; connect: ReturnType<typeof vi.fn> }> = [];
const oscillator = vi.fn(() => ({
  frequency: parameter(),
  connect: vi.fn(),
  start: vi.fn(),
  stop: vi.fn(),
  disconnect: vi.fn(),
}));
vi.stubGlobal(
  'AudioContext',
  class {
    state = 'running';
    currentTime = 0;
    destination = {};
    createOscillator = oscillator;
    createGain() {
      const gain = { gain: parameter(), connect: vi.fn(), disconnect: vi.fn() };
      gains.push(gain);
      return gain;
    }
  },
);
const { unlockAudio, playSound } = await import('./sound');
afterAll(() => vi.unstubAllGlobals());

it('routes effects through adjustable volume and mute restores the chosen level', () => {
  useSettings.getState().setVolume(0.37);
  unlockAudio();
  playSound('place');
  expect(gains[0].gain.setValueAtTime).toHaveBeenLastCalledWith(0.37, 0);
  expect(gains[1].connect).toHaveBeenCalledWith(gains[0]);
  useSettings.getState().set('sound', false);
  expect(gains[0].gain.setValueAtTime).toHaveBeenLastCalledWith(0, 0);
  const count = oscillator.mock.calls.length;
  playSound('win');
  expect(oscillator).toHaveBeenCalledTimes(count);
  useSettings.getState().set('sound', true);
  expect(gains[0].gain.setValueAtTime).toHaveBeenLastCalledWith(0.37, 0);
  useSettings.getState().setVolume(0);
  playSound('place');
  expect(oscillator).toHaveBeenCalledTimes(count);
});

it('loads previous settings without the removed background sound and validates saved volume', async () => {
  localStorage.setItem(
    'four-cubed-settings',
    JSON.stringify({ version: 1, state: { music: true, sound: false, hints: false, volume: 3 } }),
  );
  await useSettings.persist.rehydrate();
  expect(useSettings.getState()).toMatchObject({ sound: false, hints: false, volume: 1 });
  expect(useSettings.getState()).not.toHaveProperty('music');
});
