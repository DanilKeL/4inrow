import { useEffect, useState } from 'react';
import { UsersRound, Cpu, ArrowRight, Globe2 } from 'lucide-react';
import { useGame, type Mode } from '../store/gameStore';
import { secondGuestName, useAccount } from '../store/accountStore';
import type { Difficulty } from '../game/ai';
import styles from './UI.module.css';

export function Setup({
  onStart,
  onQuickStart,
  initialMode = 'local',
}: {
  onStart: () => void;
  onQuickStart: (name: string) => void;
  initialMode?: Mode;
}) {
  const [mode, setMode] = useState<Mode>(initialMode);
  const [code, setCode] = useState('');
  const onlineStatus = useGame((state) => state.onlineStatus);
  const onlineError = useGame((state) => state.onlineError);
  const online = useGame((state) => state.online);
  const connecting = onlineStatus === 'connecting';
  useEffect(() => {
    if (mode === 'online' && online && onlineStatus === 'connected') onStart();
  }, [mode, online, onlineStatus, onStart]);
  const chooseMode = (value: Mode) => {
    useGame.getState().cancelOnline();
    setMode(value);
  };
  const [difficulty, setDifficulty] = useState<Difficulty>(() => {
    try {
      const saved = localStorage.getItem('four-cubed-difficulty');
      if (saved === 'easy' || saved === 'medium' || saved === 'hard') return saved;
    } catch {
      /* Use the default without storage. */
    }
    return 'medium';
  });
  const username = useAccount((state) => state.username);
  const guestName = useAccount((state) => state.guestName);
  const identityReady = useAccount((state) => state.identityReady);
  const [secondName] = useState(secondGuestName);
  const playerName = username ?? guestName;
  return (
    <>
      <div className={`${styles.modeChoices} ${styles.threeModes}`}>
        <button
          className={mode === 'local' ? styles.selected : ''}
          onClick={() => chooseMode('local')}
        >
          <UsersRound />
          <strong>Вдвоём</strong>
          <small>На одном устройстве</small>
        </button>
        <button className={mode === 'ai' ? styles.selected : ''} onClick={() => chooseMode('ai')}>
          <Cpu />
          <strong>Против AI</strong>
          <small>Три сложности</small>
        </button>
        <button
          className={mode === 'online' ? styles.selected : ''}
          onClick={() => chooseMode('online')}
        >
          <Globe2 />
          <strong>Онлайн</strong>
          <small>По коду лобби</small>
        </button>
      </div>
      <div className={styles.nameFields}>
        <p>
          Вы играете как <strong>{playerName}</strong>
        </p>
        {mode === 'local' && (
          <p>
            Второй игрок: <strong>{secondName}</strong>
          </p>
        )}
      </div>
      {mode === 'ai' && (
        <fieldset className={styles.difficulty}>
          <legend>Сложность</legend>
          {(
            [
              ['easy', 'Легко'],
              ['medium', 'Средне'],
              ['hard', 'Сложно'],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              aria-pressed={difficulty === value}
              className={difficulty === value ? styles.selected : ''}
              onClick={() => setDifficulty(value)}
            >
              {label}
            </button>
          ))}
        </fieldset>
      )}
      {mode === 'online' ? (
        <div className={styles.onlineSetup}>
          <button
            className={styles.secondary}
            disabled={connecting || !identityReady}
            onClick={() => onQuickStart(playerName)}
          >
            Рейтинговая игра — найти соперника
          </button>
          <button
            className={styles.primary}
            disabled={connecting || !identityReady}
            onClick={() => useGame.getState().createOnline(playerName)}
          >
            {connecting ? 'Подключаемся…' : 'Создать лобби'}
            <ArrowRight size={18} />
          </button>
          <label>
            Код лобби
            <input
              aria-label="Код лобби"
              value={code}
              maxLength={5}
              autoCapitalize="characters"
              autoComplete="off"
              spellCheck={false}
              placeholder="ABCDE"
              onChange={(event) =>
                setCode(event.target.value.replace(/[^a-z]/gi, '').toUpperCase())
              }
            />
          </label>
          <button
            className={styles.secondary}
            disabled={connecting || !identityReady || !/^[A-Z]{5}$/.test(code)}
            onClick={() => useGame.getState().joinOnline(code, playerName)}
          >
            Войти в лобби
          </button>
          {onlineError && (
            <p role="alert" className={styles.onlineError}>
              {onlineError}
            </p>
          )}
        </div>
      ) : (
        <button
          className={styles.primary}
          disabled={!identityReady}
          onClick={() => {
            useGame.getState().start(mode, difficulty, [playerName, secondName]);
            onStart();
          }}
        >
          Начать игру
          <ArrowRight size={20} />
        </button>
      )}
    </>
  );
}
