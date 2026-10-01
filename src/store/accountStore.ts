import { create } from 'zustand';

const STORAGE_KEY = 'four-cubed-guest-name';
function newGuestName() {
  const number =
    typeof crypto !== 'undefined' && 'getRandomValues' in crypto
      ? (crypto.getRandomValues(new Uint32Array(1))[0] % 900000) + 100000
      : Math.floor(Math.random() * 900000) + 100000;
  return `Гость_${number}`;
}

function storedGuestName() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved && /^Гость_\d{6}$/.test(saved)) return saved;
    const name = newGuestName();
    localStorage.setItem(STORAGE_KEY, name);
    return name;
  } catch {
    return newGuestName();
  }
}

interface AccountState {
  username: string | null;
  guestName: string;
  email: string | null;
  emailVerified: boolean;
  createdAt: number | null;
  identityReady: boolean;
  loading: boolean;
  error: string;
  notice: string;
  load: () => Promise<void>;
  register: (username: string, email: string, password: string) => Promise<boolean>;
  login: (username: string, password: string) => Promise<boolean>;
  resendVerification: (identifier: string) => Promise<boolean>;
  requestPasswordReset: (email: string) => Promise<boolean>;
  completePasswordReset: (token: string, password: string) => Promise<boolean>;
  refreshProfile: () => Promise<void>;
  changePassword: (currentPassword: string, newPassword: string) => Promise<boolean>;
  clearMessages: () => void;
  logout: () => Promise<void>;
}

let initialLoad: Promise<void> | null = null;
function saveGuestName(name: string) {
  try {
    localStorage.setItem(STORAGE_KEY, name);
  } catch {
    /* Storage is optional. */
  }
}

export const useAccount = create<AccountState>((set) => ({
  username: null,
  guestName: storedGuestName(),
  email: null,
  emailVerified: false,
  createdAt: null,
  identityReady: false,
  loading: false,
  error: '',
  notice: '',
  load: () => {
    if (!initialLoad)
      initialLoad = (async () => {
        let loaded = false;
        try {
          const response = await fetch('/auth/me', {
            credentials: 'same-origin',
            signal: AbortSignal.timeout(5000),
          });
          if (!response.ok) return;
          const data = (await response.json()) as {
            username: string | null;
            guestName: string | null;
            email?: string | null;
            emailVerified?: boolean;
            createdAt?: number | null;
          };
          if (data.guestName) saveGuestName(data.guestName);
          set({
            username: data.username,
            email: data.email ?? null,
            emailVerified: Boolean(data.emailVerified),
            createdAt: data.createdAt ?? null,
            ...(data.guestName ? { guestName: data.guestName } : {}),
          });
          loaded = true;
        } catch {
          // Offline local play remains available as a guest.
        } finally {
          set({ identityReady: true });
          if (!loaded) initialLoad = null;
        }
      })();
    return initialLoad;
  },
  register: async (username, email, password) => {
    await useAccount.getState().load();
    set({ loading: true, error: '', notice: '' });
    try {
      const response = await post('/auth/register', { username, email, password });
      const data = (await response.json()) as {
        username?: string;
        verificationRequired?: boolean;
        message?: string;
        error?: string;
      };
      if (data.verificationRequired) {
        set({
          username: null,
          notice:
            data.message ??
            data.error ??
            'Аккаунт создан. Проверьте «Входящие» и папку «Спам», затем подтвердите email.',
        });
        return true;
      }
      if (!response.ok || !data.username)
        throw new Error(data.error ?? 'Не удалось зарегистрироваться.');
      set({ username: data.username, error: '' });
      return true;
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Нет связи с сервером.' });
      return false;
    } finally {
      set({ loading: false });
    }
  },
  login: async (username, password) => {
    await useAccount.getState().load();
    return submitLogin(username, password, set);
  },
  resendVerification: async (identifier) => {
    set({ loading: true, error: '', notice: '' });
    try {
      const response = await post('/auth/resend-verification', { identifier });
      const data = (await response.json()) as { message?: string; error?: string };
      if (!response.ok) throw new Error(data.error ?? 'Не удалось отправить письмо.');
      set({ notice: data.message ?? 'Письмо отправлено. Проверьте «Входящие» и папку «Спам».' });
      return true;
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Нет связи с сервером.' });
      return false;
    } finally {
      set({ loading: false });
    }
  },
  requestPasswordReset: async (email) => {
    set({ loading: true, error: '', notice: '' });
    try {
      const response = await post('/auth/password-reset/request', { email });
      const data = (await response.json()) as { message?: string; error?: string };
      if (!response.ok) throw new Error(data.error ?? 'Не удалось отправить письмо.');
      set({ notice: data.message ?? 'Если аккаунт существует, письмо отправлено.' });
      return true;
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Нет связи с сервером.' });
      return false;
    } finally {
      set({ loading: false });
    }
  },
  completePasswordReset: async (token, password) => {
    set({ loading: true, error: '', notice: '' });
    try {
      const response = await post('/auth/password-reset/complete', { token, password });
      const data = (await response.json()) as { username?: string; error?: string };
      if (!response.ok || !data.username)
        throw new Error(data.error ?? 'Не удалось изменить пароль.');
      set({ username: data.username, notice: 'Пароль изменён.', error: '' });
      return true;
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Нет связи с сервером.' });
      return false;
    } finally {
      set({ loading: false });
    }
  },
  refreshProfile: async () => {
    try {
      const response = await fetch('/auth/me', {
        credentials: 'same-origin',
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) return;
      const data = (await response.json()) as {
        username: string | null;
        email?: string | null;
        emailVerified?: boolean;
        createdAt?: number | null;
      };
      if (data.username)
        set({
          username: data.username,
          email: data.email ?? null,
          emailVerified: Boolean(data.emailVerified),
          createdAt: data.createdAt ?? null,
        });
    } catch {
      /* The cached profile remains usable while temporarily offline. */
    }
  },
  changePassword: async (currentPassword, newPassword) => {
    set({ loading: true, error: '', notice: '' });
    try {
      const response = await post('/auth/password/change', { currentPassword, newPassword });
      const data = (await response.json()) as {
        username?: string;
        message?: string;
        error?: string;
      };
      if (!response.ok || !data.username)
        throw new Error(data.error ?? 'Не удалось изменить пароль.');
      set({
        username: data.username,
        notice: data.message ?? 'Пароль изменён.',
        error: '',
      });
      return true;
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Нет связи с сервером.' });
      return false;
    } finally {
      set({ loading: false });
    }
  },
  clearMessages: () => set({ error: '', notice: '' }),
  logout: async () => {
    set({ loading: true, error: '', notice: '' });
    try {
      const response = await fetch('/auth/logout', { method: 'POST', credentials: 'same-origin' });
      if (!response.ok) throw new Error('Не удалось выйти из аккаунта.');
      const data = (await response.json()) as { guestName: string };
      saveGuestName(data.guestName);
      set({
        username: null,
        guestName: data.guestName,
        email: null,
        emailVerified: false,
        createdAt: null,
      });
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Не удалось выйти из аккаунта.' });
    } finally {
      set({ loading: false });
    }
  },
}));

async function submitLogin(
  username: string,
  password: string,
  set: (state: Partial<AccountState>) => void,
) {
  set({ loading: true, error: '', notice: '' });
  try {
    const response = await post('/auth/login', { username, password });
    const data = (await response.json()) as { username?: string; error?: string };
    if (!response.ok || !data.username) throw new Error(data.error ?? 'Не удалось выполнить вход.');
    set({ username: data.username, error: '' });
    return true;
  } catch (error) {
    set({ error: error instanceof Error ? error.message : 'Нет связи с сервером.' });
    return false;
  } finally {
    set({ loading: false });
  }
}

function post(path: string, body: object) {
  return fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  });
}

export function currentPlayerName() {
  const { username, guestName } = useAccount.getState();
  return username ?? guestName;
}

export function secondGuestName() {
  let name = newGuestName();
  while (name === currentPlayerName()) name = newGuestName();
  return name;
}
