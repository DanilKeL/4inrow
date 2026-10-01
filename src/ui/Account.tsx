import { useEffect, useMemo, useState, type FormEvent } from 'react';
import {
  Activity,
  CalendarDays,
  CheckCircle2,
  ChevronRight,
  History,
  KeyRound,
  LockKeyhole,
  LogOut,
  Mail,
  ShieldCheck,
  Target,
  Trophy,
  UserRound,
} from 'lucide-react';
import { useAccount } from '../store/accountStore';
import { useMatchHistory } from '../store/matchHistory';
import type { SavedMatch } from '../network/statistics';
import accountStyles from './Account.module.css';
import styles from './UI.module.css';

type View = 'login' | 'register' | 'forgot' | 'reset';
type SignedView = 'overview' | 'security';
const modeLabels = { local: 'Вдвоём', ai: 'Против AI', online: 'Онлайн' };

function ratingLeague(points: number) {
  if (points < 900) return { name: 'Бронза', floor: 600, ceiling: 900, next: 'Серебро' };
  if (points < 1100) return { name: 'Серебро', floor: 900, ceiling: 1100, next: 'Золото' };
  if (points < 1300) return { name: 'Золото', floor: 1100, ceiling: 1300, next: 'Платина' };
  if (points < 1500) return { name: 'Платина', floor: 1300, ceiling: 1500, next: 'Мастер' };
  return { name: 'Мастер', floor: 1500, ceiling: 1800, next: 'Высшая лига' };
}

function resultFor(match: SavedMatch, username: string) {
  if (match.ratingChange !== undefined) {
    if (match.ratingChange > 0) return { mark: 'В', label: 'Победа', tone: 'win' } as const;
    if (match.ratingChange < 0) return { mark: 'П', label: 'Поражение', tone: 'loss' } as const;
    return { mark: 'Н', label: 'Ничья', tone: 'draw' } as const;
  }
  if (!match.winner) return { mark: 'Н', label: 'Ничья', tone: 'draw' } as const;
  const seat = match.names.findIndex((name) => name === username) + 1;
  return match.winner === seat
    ? ({ mark: 'В', label: 'Победа', tone: 'win' } as const)
    : ({ mark: 'П', label: 'Поражение', tone: 'loss' } as const);
}

export function Account({ onOpenHistory }: { onOpenHistory?: () => void }) {
  const {
    username: signedIn,
    guestName,
    email: profileEmail,
    emailVerified,
    createdAt,
    loading,
    error,
    notice,
    register,
    login,
    logout,
    resendVerification,
    requestPasswordReset,
    completePasswordReset,
    refreshProfile,
    changePassword,
    clearMessages,
  } = useAccount();
  const history = useMatchHistory();
  const refreshHistory = history.refresh;
  const search = new URLSearchParams(window.location.search);
  const resetToken = search.get('reset');
  const verificationResult = search.get('emailVerified');
  const [view, setView] = useState<View>(resetToken ? 'reset' : 'register');
  const [signedView, setSignedView] = useState<SignedView>('overview');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [passwordRepeat, setPasswordRepeat] = useState('');
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [newPasswordRepeat, setNewPasswordRepeat] = useState('');
  const [localError, setLocalError] = useState('');

  useEffect(() => {
    if (signedIn) {
      void refreshHistory();
      void refreshProfile();
    }
  }, [signedIn, refreshHistory, refreshProfile]);

  const switchView = (next: View) => {
    clearMessages();
    setLocalError('');
    setPassword('');
    setPasswordRepeat('');
    setView(next);
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setLocalError('');
    if (view === 'reset') {
      if (!resetToken) return setLocalError('Ссылка сброса пароля недействительна.');
      if (password !== passwordRepeat) return setLocalError('Пароли не совпадают.');
      if (await completePasswordReset(resetToken, password)) {
        window.history.replaceState({}, '', window.location.pathname);
        setPassword('');
        setPasswordRepeat('');
      }
      return;
    }
    if (view === 'forgot') {
      if (await requestPasswordReset(email.trim())) setView('login');
      return;
    }
    if (view === 'register' && !/^[A-Za-z0-9_]{3,24}$/.test(username.trim())) {
      setLocalError('Используйте 3–24 английские буквы, цифры или символ _.');
      return;
    }
    const success = await (view === 'register'
      ? register(username.trim(), email.trim(), password)
      : login(username.trim(), password));
    if (success) {
      setPassword('');
      if (view === 'register') setView('login');
    }
  };

  const submitPassword = async (event: FormEvent) => {
    event.preventDefault();
    clearMessages();
    setLocalError('');
    if (newPassword.length < 8 || newPassword.length > 128)
      return setLocalError('Новый пароль должен содержать от 8 до 128 символов.');
    if (newPassword !== newPasswordRepeat) return setLocalError('Новые пароли не совпадают.');
    if (newPassword === currentPassword)
      return setLocalError('Новый пароль должен отличаться от текущего.');
    if (await changePassword(currentPassword, newPassword)) {
      setCurrentPassword('');
      setNewPassword('');
      setNewPasswordRepeat('');
    }
  };

  const verifiedNotice =
    verificationResult === '1'
      ? 'Email подтверждён. Вы вошли в аккаунт.'
      : verificationResult === '0'
        ? 'Ссылка подтверждения недействительна или устарела.'
        : '';
  const league = useMemo(() => ratingLeague(history.rating.points), [history.rating.points]);
  const leagueProgress = Math.max(
    0,
    Math.min(100, ((history.rating.points - league.floor) / (league.ceiling - league.floor)) * 100),
  );
  const winRate = history.statistics.total
    ? Math.round((history.statistics.wins / history.statistics.total) * 100)
    : 0;

  if (signedIn)
    return (
      <div className={accountStyles.dashboard} data-testid="account-dashboard">
        {signedView === 'overview' && (verifiedNotice || notice) && (
          <p role="status" className={styles.accountNotice}>
            {verifiedNotice || notice}
          </p>
        )}
        <nav className={accountStyles.signedTabs} aria-label="Разделы личного кабинета">
          <button
            aria-pressed={signedView === 'overview'}
            onClick={() => {
              clearMessages();
              setLocalError('');
              setSignedView('overview');
            }}
          >
            <Activity size={16} /> Обзор
          </button>
          <button
            aria-pressed={signedView === 'security'}
            onClick={() => {
              clearMessages();
              setLocalError('');
              setSignedView('security');
            }}
          >
            <ShieldCheck size={16} /> Безопасность
          </button>
        </nav>

        {signedView === 'overview' ? (
          <>
            <section className={accountStyles.profileHero}>
              <div className={accountStyles.avatar} aria-hidden="true">
                {signedIn.slice(0, 2).toUpperCase()}
              </div>
              <div className={accountStyles.identity}>
                <span>ПРОФИЛЬ ИГРОКА</span>
                <h3>{signedIn}</h3>
                <p>
                  {profileEmail ? (
                    <>
                      <Mail size={13} /> {profileEmail}
                      {emailVerified && <CheckCircle2 size={13} aria-label="Email подтверждён" />}
                    </>
                  ) : (
                    <>
                      <UserRound size={13} /> Локальный аккаунт
                    </>
                  )}
                </p>
              </div>
              <div className={accountStyles.memberSince}>
                <CalendarDays size={16} />
                <span>В игре с</span>
                <strong>
                  {createdAt
                    ? new Intl.DateTimeFormat('ru-RU', {
                        day: 'numeric',
                        month: 'short',
                        year: 'numeric',
                      }).format(createdAt)
                    : 'ранней версии'}
                </strong>
              </div>
            </section>

            <div className={accountStyles.overviewGrid}>
              <section className={accountStyles.ratingCard} data-testid="account-rating">
                <div className={accountStyles.cardHeading}>
                  <div>
                    <span>РЕЙТИНГ</span>
                    <strong>{league.name}</strong>
                  </div>
                  <Trophy size={23} />
                </div>
                <div className={accountStyles.ratingValue}>
                  <strong>{history.rating.points}</strong>
                  <span>ELO</span>
                </div>
                <div
                  className={accountStyles.ratingRail}
                  aria-label={`Прогресс лиги ${Math.round(leagueProgress)}%`}
                >
                  <span style={{ width: `${leagueProgress}%` }} />
                </div>
                <small>
                  {Math.max(0, league.ceiling - history.rating.points)} очков до уровня «
                  {league.next}»
                </small>
              </section>

              <section className={accountStyles.statisticsCard}>
                <div className={accountStyles.cardHeading}>
                  <div>
                    <span>КАРЬЕРА</span>
                    <strong>{history.rating.games} рейтинговых партий</strong>
                  </div>
                  <Target size={22} />
                </div>
                <div className={accountStyles.statistics} aria-label="Статистика аккаунта">
                  <div>
                    <strong data-testid="account-total">{history.statistics.total}</strong>
                    <span>Партий</span>
                  </div>
                  <div>
                    <strong>{history.statistics.wins}</strong>
                    <span>Побед</span>
                  </div>
                  <div>
                    <strong>{winRate}%</strong>
                    <span>Винрейт</span>
                  </div>
                  <div>
                    <strong>{history.statistics.losses}</strong>
                    <span>Поражений</span>
                  </div>
                </div>
              </section>
            </div>

            <section className={accountStyles.recentCard}>
              <div className={accountStyles.recentHeader}>
                <div>
                  <span>ПОСЛЕДНИЕ ПАРТИИ</span>
                  <strong>Недавняя форма</strong>
                </div>
                {onOpenHistory && (
                  <button onClick={onOpenHistory}>
                    Вся история <ChevronRight size={15} />
                  </button>
                )}
              </div>
              {history.loading && !history.matches.length ? (
                <p className={accountStyles.empty}>Загружаем статистику…</p>
              ) : history.matches.length ? (
                <div className={accountStyles.recentList}>
                  {history.matches.slice(0, 3).map((match) => {
                    const result = resultFor(match, signedIn);
                    return (
                      <article key={match.id}>
                        <b className={accountStyles[result.tone]}>{result.mark}</b>
                        <div>
                          <strong>{result.label}</strong>
                          <span>
                            {modeLabels[match.mode]} ·{' '}
                            {new Intl.DateTimeFormat('ru-RU', {
                              day: '2-digit',
                              month: 'short',
                            }).format(match.date)}
                          </span>
                        </div>
                        {match.ratingChange !== undefined && (
                          <em
                            className={
                              match.ratingChange >= 0 ? accountStyles.up : accountStyles.down
                            }
                          >
                            {match.ratingChange >= 0 ? '+' : ''}
                            {match.ratingChange} Elo
                          </em>
                        )}
                      </article>
                    );
                  })}
                </div>
              ) : (
                <p className={accountStyles.empty}>
                  Завершите первую партию — здесь появится ваша игровая форма.
                </p>
              )}
              {history.error && (
                <p role="alert" className={styles.onlineError}>
                  {history.error} <button onClick={() => void history.refresh()}>Повторить</button>
                </p>
              )}
            </section>

            <div className={accountStyles.accountActions}>
              {onOpenHistory && (
                <button onClick={onOpenHistory}>
                  <History size={16} /> История
                </button>
              )}
              <button
                aria-label="Выйти из аккаунта"
                onClick={() => void logout()}
                disabled={loading}
              >
                <LogOut size={16} /> Выйти
              </button>
            </div>
          </>
        ) : (
          <div className={accountStyles.securityGrid}>
            <section className={accountStyles.securityInfo}>
              <div className={accountStyles.securityIcon}>
                <ShieldCheck size={27} />
              </div>
              <span>БЕЗОПАСНОСТЬ АККАУНТА</span>
              <h3>Пароль и активные сеансы</h3>
              <p>
                После смены пароля все остальные устройства выйдут из аккаунта. Текущий сеанс
                останется активным.
              </p>
              <dl>
                <div>
                  <dt>Имя пользователя</dt>
                  <dd>{signedIn}</dd>
                </div>
                <div>
                  <dt>Email</dt>
                  <dd>{profileEmail || 'Не указан'}</dd>
                </div>
                <div>
                  <dt>Статус</dt>
                  <dd>
                    {profileEmail
                      ? emailVerified
                        ? 'Подтверждён'
                        : 'Ожидает подтверждения'
                      : 'Активен'}
                  </dd>
                </div>
              </dl>
            </section>
            <section className={accountStyles.passwordCard}>
              <div className={accountStyles.passwordHeading}>
                <LockKeyhole size={20} />
                <div>
                  <span>СМЕНА ПАРОЛЯ</span>
                  <strong>Обновите данные входа</strong>
                </div>
              </div>
              <form onSubmit={(event) => void submitPassword(event)}>
                <label>
                  Текущий пароль
                  <input
                    name="currentPassword"
                    type="password"
                    autoComplete="current-password"
                    value={currentPassword}
                    onChange={(event) => setCurrentPassword(event.target.value)}
                    required
                  />
                </label>
                <label>
                  Новый пароль
                  <input
                    name="newPassword"
                    type="password"
                    autoComplete="new-password"
                    value={newPassword}
                    onChange={(event) => setNewPassword(event.target.value)}
                    minLength={8}
                    maxLength={128}
                    required
                  />
                  <small>От 8 до 128 символов</small>
                </label>
                <label>
                  Повторите новый пароль
                  <input
                    name="newPasswordRepeat"
                    type="password"
                    autoComplete="new-password"
                    value={newPasswordRepeat}
                    onChange={(event) => setNewPasswordRepeat(event.target.value)}
                    minLength={8}
                    maxLength={128}
                    required
                  />
                </label>
                {(localError || error) && (
                  <p role="alert" className={styles.onlineError}>
                    {localError || error}
                  </p>
                )}
                {notice && (
                  <p role="status" className={styles.accountNotice}>
                    {notice}
                  </p>
                )}
                <button className={styles.primary} disabled={loading} type="submit">
                  <KeyRound size={17} /> {loading ? 'Сохраняем…' : 'Изменить пароль'}
                </button>
              </form>
            </section>
          </div>
        )}
      </div>
    );

  if (view === 'reset')
    return (
      <div className={`${styles.accountPanel} ${accountStyles.authPanel}`}>
        <p className={styles.muted}>Задайте новый пароль для аккаунта.</p>
        <form onSubmit={(event) => void submit(event)}>
          <label>
            Новый пароль
            <input
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              minLength={8}
              required
            />
          </label>
          <label>
            Повторите пароль
            <input
              type="password"
              autoComplete="new-password"
              value={passwordRepeat}
              onChange={(event) => setPasswordRepeat(event.target.value)}
              minLength={8}
              required
            />
          </label>
          {(localError || error) && (
            <p role="alert" className={styles.onlineError}>
              {localError || error}
            </p>
          )}
          <button className={styles.primary} disabled={loading} type="submit">
            {loading ? 'Сохраняем…' : 'Изменить пароль'}
          </button>
        </form>
      </div>
    );

  if (view === 'forgot')
    return (
      <div className={`${styles.accountPanel} ${accountStyles.authPanel}`}>
        <p className={styles.muted}>Пришлём ссылку для создания нового пароля.</p>
        <form onSubmit={(event) => void submit(event)}>
          <label>
            Email
            <input
              name="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>
          {error && (
            <p role="alert" className={styles.onlineError}>
              {error}
            </p>
          )}
          <button className={styles.primary} disabled={loading} type="submit">
            {loading ? 'Отправляем…' : 'Получить ссылку'}
          </button>
          <button className={styles.secondary} type="button" onClick={() => switchView('login')}>
            Вернуться ко входу
          </button>
        </form>
      </div>
    );

  return (
    <div className={`${styles.accountPanel} ${accountStyles.authPanel}`}>
      <div className={accountStyles.guestIntro}>
        <UserRound size={20} />
        <div>
          <span>ТЕКУЩИЙ ПРОФИЛЬ</span>
          <strong>{guestName}</strong>
        </div>
      </div>
      {(verifiedNotice || notice) && (
        <p role="status" className={styles.accountNotice}>
          {verifiedNotice || notice}
        </p>
      )}
      <div className={styles.accountTabs}>
        <button
          aria-pressed={view === 'register'}
          className={view === 'register' ? styles.selected : ''}
          onClick={() => switchView('register')}
        >
          Регистрация
        </button>
        <button
          aria-pressed={view === 'login'}
          className={view === 'login' ? styles.selected : ''}
          onClick={() => switchView('login')}
        >
          Вход
        </button>
      </div>
      <form onSubmit={(event) => void submit(event)}>
        <label>
          Имя пользователя
          <input
            name="username"
            autoComplete="username"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            pattern={view === 'register' ? '[A-Za-z0-9_]{3,24}' : undefined}
            title={
              view === 'register' ? 'От 3 до 24 английских букв, цифр или символов _.' : undefined
            }
            autoCapitalize="none"
            spellCheck={false}
            minLength={3}
            maxLength={24}
            required
          />
          {view === 'register' && (
            <small className={styles.inputHint}>Английские буквы, цифры и _ · 3–24 символа</small>
          )}
        </label>
        {view === 'register' && (
          <label>
            Email
            <input
              name="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>
        )}
        <label>
          Пароль
          <input
            name="password"
            type="password"
            autoComplete={view === 'register' ? 'new-password' : 'current-password'}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            minLength={view === 'register' ? 8 : undefined}
            required
          />
        </label>
        {(localError || error) && (
          <p role="alert" className={styles.onlineError}>
            {localError || error}
          </p>
        )}
        <button className={styles.primary} disabled={loading} type="submit">
          {loading ? 'Подождите…' : view === 'register' ? 'Зарегистрироваться' : 'Войти'}
        </button>
        {view === 'login' && (
          <>
            <button className={styles.secondary} type="button" onClick={() => switchView('forgot')}>
              Забыли пароль?
            </button>
            {(email || username) && (
              <button
                className={styles.textButton}
                type="button"
                disabled={loading}
                onClick={() => void resendVerification(email.trim() || username.trim())}
              >
                Отправить подтверждение ещё раз
              </button>
            )}
          </>
        )}
      </form>
    </div>
  );
}
