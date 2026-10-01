import { type FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import {
  Ban,
  BarChart3,
  Check,
  ChevronLeft,
  ChevronRight,
  CircleUserRound,
  Copy,
  KeyRound,
  LogOut,
  RefreshCw,
  Save,
  Search,
  ShieldCheck,
  UsersRound,
  X,
} from 'lucide-react';
import styles from './AdminApp.module.css';
import AnalyticsDashboard from './AnalyticsDashboard';

type PlayerAccount = {
  username: string;
  createdAt: number | null;
  email: string;
  emailVerified: boolean;
  disabled: boolean;
  rating: { points: number; games: number };
  statistics: { total: number; wins: number; losses: number; draws: number };
};

const dateFormatter = new Intl.DateTimeFormat('ru-RU', {
  dateStyle: 'medium',
  timeStyle: 'short',
});
const registrationDate = (createdAt: number | null) =>
  createdAt ? dateFormatter.format(new Date(createdAt)) : 'До обновления';

type AccountPage = {
  accounts: PlayerAccount[];
  total: number;
  page: number;
  pageSize: number;
};

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    credentials: 'same-origin',
    ...init,
    headers: init?.body ? { 'Content-Type': 'application/json', ...init.headers } : init?.headers,
  });
  const data = (await response.json()) as T & { error?: string };
  if (!response.ok) throw new Error(data.error ?? 'Операция не выполнена.');
  return data;
}

export default function AdminApp() {
  const [tab, setTab] = useState<'accounts' | 'analytics'>('analytics');
  const [checking, setChecking] = useState(true);
  const [configured, setConfigured] = useState(true);
  const [authenticated, setAuthenticated] = useState(false);
  const [loginError, setLoginError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const [data, setData] = useState<AccountPage>({ accounts: [], total: 0, page: 1, pageSize: 25 });
  const [selected, setSelected] = useState<PlayerAccount | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const onUnauthorized = useCallback(() => setAuthenticated(false), []);

  useEffect(() => {
    document.title = 'FOUR³ · Администрирование';
    let robots = document.querySelector<HTMLMetaElement>('meta[name="robots"]');
    if (!robots) {
      robots = document.createElement('meta');
      robots.name = 'robots';
      document.head.append(robots);
    }
    robots.content = 'noindex,nofollow';
    void api<{ configured: boolean; authenticated: boolean }>('/admin-api/me')
      .then((result) => {
        setConfigured(result.configured);
        setAuthenticated(result.authenticated);
      })
      .catch((reason: unknown) => setLoginError(String(reason)))
      .finally(() => setChecking(false));
  }, []);

  const load = useCallback(async () => {
    if (!authenticated) return;
    setBusy(true);
    setError('');
    try {
      const result = await api<AccountPage>(
        `/admin-api/accounts?q=${encodeURIComponent(query)}&page=${page}&pageSize=25`,
      );
      setData(result);
      setSelected((current) => {
        if (!current) return result.accounts[0] ?? null;
        return result.accounts.find((account) => account.username === current.username) ?? null;
      });
    } catch (reason) {
      if (reason instanceof Error && reason.message === 'Войдите в админ-панель.')
        setAuthenticated(false);
      else setError(reason instanceof Error ? reason.message : 'Не удалось загрузить игроков.');
    } finally {
      setBusy(false);
    }
  }, [authenticated, page, query]);

  useEffect(() => {
    const timeout = window.setTimeout(() => void load(), 250);
    return () => window.clearTimeout(timeout);
  }, [load]);

  const pages = Math.max(1, Math.ceil(data.total / data.pageSize));
  const verifiedCount = useMemo(
    () => data.accounts.filter((account) => account.emailVerified).length,
    [data.accounts],
  );

  if (checking)
    return (
      <main className={styles.centered}>
        <span className={styles.spinner} />
        <p>Проверяем доступ…</p>
      </main>
    );

  if (!authenticated)
    return (
      <main className={styles.loginPage}>
        <section className={styles.loginCard}>
          <div className={styles.brandMark}>4</div>
          <div>
            <p className={styles.eyebrow}>FOUR³ CONTROL</p>
            <h1>Администрирование</h1>
            <p className={styles.loginLead}>Аккаунты игроков, рейтинг и доступ.</p>
          </div>
          {!configured ? (
            <p className={styles.error}>Админ-панель не настроена на сервере.</p>
          ) : (
            <form
              onSubmit={async (event: FormEvent<HTMLFormElement>) => {
                event.preventDefault();
                setBusy(true);
                setLoginError('');
                const form = new FormData(event.currentTarget);
                try {
                  await api('/admin-api/login', {
                    method: 'POST',
                    body: JSON.stringify({
                      username: form.get('username'),
                      password: form.get('password'),
                    }),
                  });
                  setAuthenticated(true);
                } catch (reason) {
                  setLoginError(reason instanceof Error ? reason.message : 'Не удалось войти.');
                } finally {
                  setBusy(false);
                }
              }}
            >
              <label>
                Логин
                <input name="username" autoComplete="username" defaultValue="admin" required />
              </label>
              <label>
                Пароль
                <input name="password" type="password" autoComplete="current-password" required />
              </label>
              {loginError && <p className={styles.error}>{loginError}</p>}
              <button className={styles.primary} disabled={busy}>
                <ShieldCheck size={18} /> {busy ? 'Входим…' : 'Войти'}
              </button>
            </form>
          )}
          <a href="/">Вернуться в игру</a>
        </section>
      </main>
    );

  return (
    <main className={styles.adminPage}>
      <header className={styles.header}>
        <div className={styles.brand}>
          <span className={styles.brandMark}>4</span>
          <div>
            <p className={styles.eyebrow}>FOUR³ CONTROL</p>
            <strong>Администрирование</strong>
          </div>
        </div>
        <div className={styles.headerActions}>
          <a href="/">Открыть игру</a>
          <button
            className={styles.iconButton}
            aria-label="Выйти из админ-панели"
            onClick={async () => {
              await api('/admin-api/logout', { method: 'POST', body: '{}' }).catch(() => null);
              setAuthenticated(false);
            }}
          >
            <LogOut size={19} />
          </button>
        </div>
      </header>

      <nav className={styles.navigation} aria-label="Администрирование">
        <button
          aria-current={tab === 'analytics' ? 'page' : undefined}
          onClick={() => setTab('analytics')}
        >
          <BarChart3 size={17} />
          Статистика
        </button>
        <button
          aria-current={tab === 'accounts' ? 'page' : undefined}
          onClick={() => setTab('accounts')}
        >
          <UsersRound size={17} />
          Игроки
        </button>
      </nav>
      {tab === 'analytics' ? (
        <AnalyticsDashboard onUnauthorized={onUnauthorized} />
      ) : (
        <section className={styles.content}>
          <div className={styles.toolbar}>
            <div>
              <h1>Аккаунты</h1>
              <p>{data.total} зарегистрированных игроков</p>
            </div>
            <label className={styles.search}>
              <Search size={18} />
              <input
                aria-label="Поиск игроков"
                placeholder="Имя или email"
                value={query}
                onChange={(event) => {
                  setQuery(event.target.value);
                  setPage(1);
                }}
              />
              {query && (
                <button aria-label="Очистить поиск" onClick={() => setQuery('')}>
                  <X size={16} />
                </button>
              )}
            </label>
            <button className={styles.refresh} aria-label="Обновить" onClick={() => void load()}>
              <RefreshCw size={18} className={busy ? styles.spinning : ''} />
            </button>
          </div>

          <div className={styles.statsStrip}>
            <span>
              <UsersRound size={17} /> На странице <strong>{data.accounts.length}</strong>
            </span>
            <span>
              <Check size={17} /> Подтверждённых email <strong>{verifiedCount}</strong>
            </span>
            <span>
              <Ban size={17} /> Заблокировано{' '}
              <strong>{data.accounts.filter((account) => account.disabled).length}</strong>
            </span>
          </div>

          {error && <p className={styles.errorBanner}>{error}</p>}
          {notice && <p className={styles.noticeBanner}>{notice}</p>}

          <div className={styles.workspace}>
            <section className={styles.listPanel} aria-label="Список игроков">
              <div className={styles.tableHeader}>
                <span>Игрок</span>
                <span>Регистрация</span>
                <span>Elo</span>
                <span>Игры</span>
                <span>Статус</span>
              </div>
              <div className={styles.rows}>
                {data.accounts.map((account) => (
                  <button
                    key={account.username}
                    className={`${styles.row} ${selected?.username === account.username ? styles.rowSelected : ''}`}
                    onClick={() => {
                      setSelected(account);
                      setNotice('');
                      setError('');
                    }}
                  >
                    <span className={styles.identity}>
                      <span className={styles.avatar}>
                        {account.username.slice(0, 1).toUpperCase()}
                      </span>
                      <span>
                        <strong>{account.username}</strong>
                        <small>{account.email || 'Email не указан'}</small>
                      </span>
                    </span>
                    <span className={styles.registration}>
                      {registrationDate(account.createdAt)}
                    </span>
                    <strong>{account.rating.points}</strong>
                    <span>{account.statistics.total}</span>
                    <span className={account.disabled ? styles.blocked : styles.active}>
                      {account.disabled ? 'Блок' : 'Активен'}
                    </span>
                  </button>
                ))}
                {!busy && !data.accounts.length && (
                  <div className={styles.empty}>
                    <CircleUserRound size={36} />
                    <strong>Игроки не найдены</strong>
                    <p>Измените поисковый запрос.</p>
                  </div>
                )}
              </div>
              <footer className={styles.pagination}>
                <span>
                  Страница {page} из {pages}
                </span>
                <div>
                  <button disabled={page <= 1} onClick={() => setPage((value) => value - 1)}>
                    <ChevronLeft size={18} />
                  </button>
                  <button disabled={page >= pages} onClick={() => setPage((value) => value + 1)}>
                    <ChevronRight size={18} />
                  </button>
                </div>
              </footer>
            </section>

            <AccountEditor
              key={selected?.username ?? 'none'}
              account={selected}
              onUpdated={(account, message) => {
                setSelected(account);
                setNotice(message);
                setData((current) => ({
                  ...current,
                  accounts: current.accounts.map((item) =>
                    item.username === selected?.username ? account : item,
                  ),
                }));
              }}
              onDeleted={(username) => {
                setSelected(null);
                setNotice(`Аккаунт ${username} удалён.`);
                setData((current) => ({
                  ...current,
                  total: Math.max(0, current.total - 1),
                  accounts: current.accounts.filter((item) => item.username !== username),
                }));
              }}
              onError={setError}
            />
          </div>
        </section>
      )}
    </main>
  );
}

function AccountEditor({
  account,
  onUpdated,
  onDeleted,
  onError,
}: {
  account: PlayerAccount | null;
  onUpdated: (account: PlayerAccount, message: string) => void;
  onDeleted: (username: string) => void;
  onError: (message: string) => void;
}) {
  const [saving, setSaving] = useState(false);
  const [confirmReset, setConfirmReset] = useState(false);
  const [temporary, setTemporary] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteText, setDeleteText] = useState('');
  if (!account)
    return (
      <aside className={styles.editorEmpty}>
        <CircleUserRound size={42} />
        <p>Выберите игрока для редактирования.</p>
      </aside>
    );
  return (
    <aside className={styles.editor}>
      <div className={styles.editorHeading}>
        <div className={styles.largeAvatar}>{account.username.slice(0, 1).toUpperCase()}</div>
        <div>
          <span>Карточка игрока</span>
          <h2>{account.username}</h2>
          <small className={styles.registeredAt}>
            Регистрация: {registrationDate(account.createdAt)}
          </small>
        </div>
      </div>
      <div className={styles.recordStats}>
        <span>
          <strong>{account.statistics.wins}</strong> побед
        </span>
        <span>
          <strong>{account.statistics.losses}</strong> поражений
        </span>
        <span>
          <strong>{account.statistics.draws}</strong> ничьих
        </span>
      </div>
      <form
        onSubmit={async (event: FormEvent<HTMLFormElement>) => {
          event.preventDefault();
          setSaving(true);
          onError('');
          const form = new FormData(event.currentTarget);
          try {
            const result = await api<{ account: PlayerAccount }>('/admin-api/accounts', {
              method: 'PATCH',
              body: JSON.stringify({
                originalUsername: account.username,
                username: form.get('username'),
                email: form.get('email'),
                emailVerified: form.get('emailVerified') === 'on',
                disabled: form.get('disabled') === 'on',
                rating: Number(form.get('rating')),
              }),
            });
            onUpdated(result.account, 'Изменения сохранены.');
          } catch (reason) {
            onError(reason instanceof Error ? reason.message : 'Не удалось сохранить изменения.');
          } finally {
            setSaving(false);
          }
        }}
      >
        <label>
          Имя пользователя
          <input name="username" defaultValue={account.username} required />
        </label>
        <label>
          Email
          <input name="email" type="email" defaultValue={account.email} placeholder="Не указан" />
        </label>
        <div className={styles.fieldGrid}>
          <label>
            Elo
            <input
              name="rating"
              type="number"
              min="0"
              max="1000000"
              defaultValue={account.rating.points}
              required
            />
          </label>
          <label>
            Рейтинговых игр
            <input value={account.rating.games} disabled readOnly />
          </label>
        </div>
        <label className={styles.checkbox}>
          <input name="emailVerified" type="checkbox" defaultChecked={account.emailVerified} />
          <span>
            <strong>Email подтверждён</strong>
            <small>Разрешает вход без повторной проверки почты.</small>
          </span>
        </label>
        <label className={`${styles.checkbox} ${styles.dangerCheck}`}>
          <input name="disabled" type="checkbox" defaultChecked={account.disabled} />
          <span>
            <strong>Заблокировать аккаунт</strong>
            <small>Вход и активные игровые сессии будут закрыты.</small>
          </span>
        </label>
        <button className={styles.primary} disabled={saving}>
          <Save size={18} /> {saving ? 'Сохраняем…' : 'Сохранить изменения'}
        </button>
      </form>

      <div className={styles.securityBlock}>
        <div>
          <KeyRound size={19} />
          <span>
            <strong>Сброс пароля</strong>
            <small>Все сессии игрока завершатся.</small>
          </span>
        </div>
        {!confirmReset ? (
          <button
            className={styles.secondary}
            onClick={() => {
              setConfirmReset(true);
              setTemporary('');
            }}
          >
            Сбросить пароль
          </button>
        ) : (
          <div className={styles.confirmReset}>
            <p>Создать новый временный пароль для {account.username}?</p>
            <div>
              <button className={styles.secondary} onClick={() => setConfirmReset(false)}>
                Отмена
              </button>
              <button
                className={styles.dangerButton}
                onClick={async () => {
                  setSaving(true);
                  onError('');
                  try {
                    const result = await api<{ temporaryPassword: string }>(
                      '/admin-api/accounts/reset-password',
                      {
                        method: 'POST',
                        body: JSON.stringify({ username: account.username }),
                      },
                    );
                    setTemporary(result.temporaryPassword);
                    setConfirmReset(false);
                  } catch (reason) {
                    onError(
                      reason instanceof Error ? reason.message : 'Не удалось сбросить пароль.',
                    );
                  } finally {
                    setSaving(false);
                  }
                }}
              >
                Создать пароль
              </button>
            </div>
          </div>
        )}
        {temporary && (
          <div className={styles.temporaryPassword}>
            <span>Временный пароль показывается один раз</span>
            <div>
              <code>{temporary}</code>
              <button
                aria-label="Скопировать временный пароль"
                onClick={() => void navigator.clipboard.writeText(temporary)}
              >
                <Copy size={17} />
              </button>
            </div>
          </div>
        )}
      </div>

      <div className={styles.deleteBlock}>
        <div>
          <Ban size={19} />
          <span>
            <strong>Удаление аккаунта</strong>
            <small>Аккаунт, статистика, Elo и история будут удалены безвозвратно.</small>
          </span>
        </div>
        {!confirmDelete ? (
          <button className={styles.deleteLink} onClick={() => setConfirmDelete(true)}>
            Удалить аккаунт
          </button>
        ) : (
          <div className={styles.deleteConfirm}>
            <p>
              Для подтверждения введите <strong>{account.username}</strong>
            </p>
            <input
              aria-label="Подтверждение удаления"
              value={deleteText}
              onChange={(event) => setDeleteText(event.target.value)}
              autoComplete="off"
            />
            <div>
              <button
                className={styles.secondary}
                onClick={() => {
                  setConfirmDelete(false);
                  setDeleteText('');
                }}
              >
                Отмена
              </button>
              <button
                className={styles.dangerButton}
                disabled={saving || deleteText !== account.username}
                onClick={async () => {
                  setSaving(true);
                  onError('');
                  try {
                    await api('/admin-api/accounts', {
                      method: 'DELETE',
                      body: JSON.stringify({
                        username: account.username,
                        confirmation: deleteText,
                      }),
                    });
                    onDeleted(account.username);
                  } catch (reason) {
                    onError(
                      reason instanceof Error ? reason.message : 'Не удалось удалить аккаунт.',
                    );
                  } finally {
                    setSaving(false);
                  }
                }}
              >
                Удалить безвозвратно
              </button>
            </div>
          </div>
        )}
      </div>
    </aside>
  );
}
