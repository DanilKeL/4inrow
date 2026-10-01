import { Volume2, Sparkles, MousePointer2, ScanLine } from 'lucide-react';
import { useSettings } from '../store/settingsStore';
import styles from './UI.module.css';

const options = [
  {
    key: 'animations',
    label: 'Анимации',
    description: 'Падение фишек и плавная камера',
    icon: Sparkles,
  },
  {
    key: 'hints',
    label: 'Предпросмотр хода',
    description: 'Показывать фишку при наведении',
    icon: MousePointer2,
  },
  {
    key: 'xrayDefault',
    label: 'Рентген по умолчанию',
    description: 'Прозрачные фишки в новой партии',
    icon: ScanLine,
  },
] as const;
export function Settings() {
  const settings = useSettings();
  return (
    <>
      <div className={styles.settingsList}>
        <label className={styles.setting}>
          <Volume2 size={20} />
          <span>
            <strong>
              Громкость звуков <output>{Math.round(settings.volume * 100)}%</output>
            </strong>
            <input
              className={styles.volumeSlider}
              type="range"
              min="0"
              max="100"
              step="1"
              aria-label="Громкость звуков"
              aria-valuetext={String(Math.round(settings.volume * 100)) + '%'}
              value={Math.round(settings.volume * 100)}
              onChange={(event) => settings.setVolume(Number(event.target.value) / 100)}
            />
            {!settings.sound && <small>Звук выключен кнопкой в шапке</small>}
          </span>
        </label>
        {options.map(({ key, label, description, icon: Icon }) => (
          <label className={styles.setting} key={key}>
            <Icon size={20} />
            <span>
              <strong>{label}</strong>
              <small>{description}</small>
            </span>
            <input
              type="checkbox"
              role="switch"
              checked={settings[key]}
              onChange={(event) => settings.set(key, event.target.checked)}
              aria-label={label}
            />
          </label>
        ))}
      </div>
    </>
  );
}
