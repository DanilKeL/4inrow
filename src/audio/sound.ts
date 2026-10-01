import { useSettings } from '../store/settingsStore';

let context: AudioContext | undefined;
let master: GainNode | undefined;
function updateVolume() {
  if (!context || !master) return;
  const { sound, volume } = useSettings.getState();
  master.gain.setValueAtTime(sound ? volume : 0, context.currentTime);
}
useSettings.subscribe(updateVolume);

export function unlockAudio() {
  if (!context) {
    context = new AudioContext();
    master = context.createGain();
    master.connect(context.destination);
  }
  updateVolume();
  if (context.state === 'suspended') void context.resume();
}

export function playSound(kind: 'place' | 'invalid' | 'win' | 'click' | 'match') {
  if (
    !context ||
    context.state !== 'running' ||
    !useSettings.getState().sound ||
    useSettings.getState().volume === 0
  )
    return;
  const frequencies =
    kind === 'match'
      ? [660, 880, 660, 1046]
      : kind === 'win'
        ? [392, 494, 587, 784]
        : [kind === 'invalid' ? 130 : kind === 'place' ? 380 : 640];
  frequencies.forEach((frequency, i) => {
    const oscillator = context!.createOscillator();
    const gain = context!.createGain();
    const time = context!.currentTime + i * 0.13;
    oscillator.type = kind === 'place' ? 'triangle' : 'sine';
    oscillator.frequency.setValueAtTime(frequency, time);
    oscillator.frequency.exponentialRampToValueAtTime(
      kind === 'place' ? 100 : frequency,
      time + 0.1,
    );
    gain.gain.setValueAtTime(0, time);
    gain.gain.linearRampToValueAtTime(kind === 'win' ? 0.08 : 0.12, time + 0.005);
    gain.gain.exponentialRampToValueAtTime(0.001, time + 0.2);
    oscillator.connect(gain);
    gain.connect(master!);
    oscillator.start(time);
    oscillator.stop(time + 0.25);
    oscillator.onended = () => {
      oscillator.disconnect();
      gain.disconnect();
    };
  });
}
