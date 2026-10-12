import { useEffect, useRef, useState } from 'react';
import { useAccount } from '../store/accountStore';
import { loadTelegramLogin, telegramLoginSDK } from '../network/telegramLogin';
import { telegramApp } from '../telegram/bridge';
import accountStyles from './Account.module.css';
import styles from './UI.module.css';

type Challenge = { nonce: string; clientId: string | null; miniApp: boolean };
export function TelegramLogin({ purpose = 'login' }: { purpose?: 'login' | 'link' }) {
  const { username, loading, telegramLogin, clearMessages, telegramRegistration } = useAccount();
  const [challenge, setChallenge] = useState<Challenge | null>(null);
  const [available, setAvailable] = useState(false);
  const [error, setError] = useState('');
  const [active, setActive] = useState(false);
  const [generation, setGeneration] = useState(0);
  const mounted = useRef(false);
  const loginAttempt = useRef(Symbol());
  useEffect(() => {
    mounted.current = true;
    let cancelled = false;
    const controller = new AbortController();
    setChallenge(null);
    async function prepare() {
      try {
        if (!navigator.onLine) return;
        const config = (await fetch('/auth/telegram/config', {
          credentials: 'same-origin',
          signal: AbortSignal.any([controller.signal, AbortSignal.timeout(10000)]),
        }).then((r) => r.json())) as Omit<Challenge, 'nonce'>;
        const miniApp = Boolean(telegramApp()?.initData && config.miniApp);
        if (!miniApp && !config.clientId) {
          if (!cancelled) setAvailable(false);
          return;
        }
        if (!cancelled) setAvailable(true);
        // Resolve SDK and server state before a click, preserving popup user activation.
        if (!miniApp) await loadTelegramLogin();
        await useAccount.getState().load();
        if (cancelled) return;
        const response = await fetch('/auth/telegram/begin', {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ purpose }),
          signal: AbortSignal.any([controller.signal, AbortSignal.timeout(10000)]),
        });
        const data = (await response.json()) as Challenge & { error?: string };
        if (!response.ok) throw new Error(data.error ?? 'Не удалось подготовить вход.');
        if (!cancelled) {
          setChallenge(data);
          setError('');
        }
      } catch (error) {
        if (!cancelled) setError(error instanceof Error ? error.message : 'Нет связи с сервером.');
      }
    }
    void prepare();
    return () => {
      cancelled = true;
      mounted.current = false;
      controller.abort();
      loginAttempt.current = Symbol();
      telegramLoginSDK()?.close?.();
    };
  }, [purpose, username, generation]);

  const retry = () => {
    if (mounted.current) {
      setActive(false);
      setChallenge(null);
      setGeneration((value) => value + 1);
    }
  };
  const complete = async (body: { nonce: string; initData?: string; idToken?: string }) => {
    await telegramLogin(body);
    if (mounted.current) setActive(false);
    if (!useAccount.getState().telegramRegistration) retry();
  };
  const start = () => {
    if (!challenge) {
      setGeneration((value) => value + 1);
      return;
    }
    clearMessages();
    setError('');
    setActive(true);
    const attempt = Symbol();
    loginAttempt.current = attempt;
    const initData = telegramApp()?.initData;
    if (initData && challenge.miniApp) {
      void complete({ nonce: challenge.nonce, initData });
      return;
    }
    const sdk = telegramLoginSDK();
    if (!sdk || !challenge.clientId) {
      retry();
      return;
    }
    try {
      const result = sdk.auth(
        {
          client_id: Number(challenge.clientId),
          scope: ['profile'],
          nonce: challenge.nonce,
          lang: 'ru',
        },
        (data) => {
          if (!mounted.current || attempt !== loginAttempt.current) return;
          if (data?.id_token) void complete({ nonce: challenge.nonce, idToken: data.id_token });
          else {
            if (data?.error && !/cancel|closed/i.test(data.error))
              setError('Telegram не подтвердил вход. Попробуйте снова.');
            retry();
          }
        },
      );
      if (result instanceof Promise)
        void result.catch(() => {
          if (mounted.current && attempt === loginAttempt.current) {
            setError('Не удалось открыть вход Telegram.');
            retry();
          }
        });
    } catch {
      setError('Не удалось открыть вход Telegram.');
      retry();
    }
  };
  if (telegramRegistration)
    return <TelegramRegistration suggested={telegramRegistration} onCancel={retry} />;
  if (!available) return null;
  return (
    <div className={accountStyles.telegramSection}>
      <button
        type="button"
        className={accountStyles.telegramButton}
        disabled={loading || active || (!challenge && !error)}
        onClick={start}
      >
        <svg width="19" height="19" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M21.5 3.2 2.6 10.5c-1.3.5-1.3 1.2-.2 1.5l4.8 1.5 1.8 5.7c.2.6.4.8.8.8.4 0 .7-.2 1-.5l2.4-2.3 5 3.7c.9.5 1.5.2 1.7-.8l3.2-15.3c.3-1.3-.5-1.9-1.6-1.6ZM8 13.1 19 6.2c.5-.3.9-.1.5.2l-9.1 8.3-.4 3.9-2-5.5Z" />
        </svg>
        {active || loading
          ? 'Подождите…'
          : purpose === 'link'
            ? 'Привязать Telegram'
            : 'Войти через Telegram'}
      </button>
      {active && (
        <button
          type="button"
          className={styles.textButton}
          disabled={loading}
          onClick={() => {
            loginAttempt.current = Symbol();
            telegramLoginSDK()?.close?.();
            retry();
          }}
        >
          Отменить
        </button>
      )}
      {error && (
        <p role="alert" className={styles.onlineError}>
          {error}
        </p>
      )}
    </div>
  );
}

function TelegramRegistration({
  suggested,
  onCancel,
}: {
  suggested: string;
  onCancel: () => void;
}) {
  const [username, setUsername] = useState(suggested);
  const { loading, error, registerTelegram, cancelTelegramRegistration } = useAccount();
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        void registerTelegram(username.trim());
      }}
    >
      <label>
        Имя пользователя
        <input
          name="telegramUsername"
          autoComplete="username"
          autoCapitalize="none"
          spellCheck={false}
          value={username}
          onChange={(event) => setUsername(event.target.value)}
          pattern="[A-Za-z0-9_]{3,24}"
          minLength={3}
          maxLength={24}
          required
        />
        <small className={styles.inputHint}>Английские буквы, цифры и _ · 3–24 символа</small>
      </label>
      {error && (
        <p role="alert" className={styles.onlineError}>
          {error}
        </p>
      )}
      <button type="submit" className={styles.primary} disabled={loading}>
        {loading ? 'Сохраняем…' : 'Завершить регистрацию'}
      </button>
      <button
        type="button"
        className={styles.secondary}
        disabled={loading}
        onClick={() => {
          void cancelTelegramRegistration().then(onCancel);
        }}
      >
        Отменить
      </button>
    </form>
  );
}
