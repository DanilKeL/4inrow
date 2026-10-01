// @vitest-environment jsdom
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
const mock = vi.hoisted(() => ({
  play: vi.fn(),
  unlock: vi.fn(),
  settings: { sound: true, volume: 0.5 },
}));
vi.mock('../audio/sound', () => ({ playSound: mock.play, unlockAudio: mock.unlock }));
vi.mock('../store/settingsStore', () => ({ useSettings: { getState: () => mock.settings } }));
let clearMatchAlert: typeof import('./matchAlert').clearMatchAlert;
let notifyMatchFound: typeof import('./matchAlert').notifyMatchFound;
let prepareMatchAlerts: typeof import('./matchAlert').prepareMatchAlerts;
let matchAlertStatus: typeof import('./matchAlert').matchAlertStatus;
beforeEach(async () => {
  vi.resetModules();
  ({ clearMatchAlert, notifyMatchFound, prepareMatchAlerts, matchAlertStatus } =
    await import('./matchAlert'));
  vi.stubGlobal('isSecureContext', true);
});
const shown: Array<{
  title: string;
  options: NotificationOptions;
  close: ReturnType<typeof vi.fn>;
}> = [];
function notifications(permission = 'granted') {
  vi.stubGlobal(
    'Notification',
    class {
      static permission = permission;
      static requestPermission = vi.fn(async () => 'granted');
      close = vi.fn();
      constructor(title: string, options: NotificationOptions) {
        shown.push({ title, options, close: this.close });
      }
    },
  );
}
afterEach(() => {
  clearMatchAlert();
  vi.unstubAllGlobals();
  vi.clearAllMocks();
  shown.length = 0;
  mock.settings.sound = true;
});
it('requests permission during search activation, alerts once and closes on cancellation', async () => {
  notifications();
  vi.stubGlobal('isSecureContext', true);
  document.title = 'FOUR';
  prepareMatchAlerts();
  expect(mock.unlock).toHaveBeenCalledOnce();
  notifyMatchFound('one', 'Alice', Date.now() + 15000);
  notifyMatchFound('one', 'Alice', Date.now() + 15000);
  await vi.waitFor(() => expect(shown).toHaveLength(1));
  expect(mock.play).toHaveBeenCalledExactlyOnceWith('match');
  expect(shown).toHaveLength(1);
  expect(shown[0].options.body).toContain('Alice');
  expect(document.title).toContain('Соперник найден');
  clearMatchAlert();
  expect(shown[0].close).toHaveBeenCalled();
  expect(document.title).toBe('FOUR');
});
it('works with denied permission and never emits expired or cancelled notifications', async () => {
  notifications('denied');
  notifyMatchFound('old', 'Alice', Date.now() - 1);
  expect(mock.play).not.toHaveBeenCalled();
  notifyMatchFound('current', 'Alice', Date.now() + 15000);
  await Promise.resolve();
  expect(shown).toHaveLength(0);
  expect(mock.play).toHaveBeenCalledOnce();
  notifications();
  notifyMatchFound('cancelled', 'Bob', Date.now() + 15000);
  clearMatchAlert();
  await Promise.resolve();
  expect(shown).toHaveLength(0);
});
it('honors mute for the system notification and asks only when permission is undecided', async () => {
  notifications('default');
  vi.stubGlobal('isSecureContext', true);
  prepareMatchAlerts();
  expect(Notification.requestPermission).toHaveBeenCalledOnce();
  notifications();
  mock.settings.sound = false;
  notifyMatchFound('muted', 'Bob', Date.now() + 15000);
  await vi.waitFor(() => expect(shown).toHaveLength(1));
  expect(shown[0].options.silent).toBe(true);
});

function serviceWorker() {
  const registration = {
    active: null,
    showNotification: vi.fn(async () => {}),
    getNotifications: vi.fn(async () => []),
  };
  const register = vi.fn(async () => registration);
  vi.stubGlobal('navigator', { serviceWorker: { register, ready: Promise.resolve(registration) } });
  return { registration, register };
}

it('waits for permission when a match arrives while the mobile permission prompt is open', async () => {
  notifications('default');
  const { registration } = serviceWorker();
  let grant!: (permission: NotificationPermission) => void;
  vi.mocked(Notification.requestPermission).mockImplementation(
    () =>
      new Promise((resolve) => {
        grant = resolve;
      }),
  );
  prepareMatchAlerts();
  notifyMatchFound('fast-match', 'Alice', Date.now() + 15000);
  expect(matchAlertStatus()).toBe('prompting');
  expect(registration.showNotification).not.toHaveBeenCalled();
  grant('granted');
  await vi.waitFor(() => expect(registration.showNotification).toHaveBeenCalledOnce());
  expect(shown).toHaveLength(0); // Mobile delivery must use the worker, never the constructor.
});

it('does not deliver a cancelled match when permission is granted later', async () => {
  notifications('default');
  const { registration } = serviceWorker();
  let grant!: (permission: NotificationPermission) => void;
  vi.mocked(Notification.requestPermission).mockImplementation(
    () =>
      new Promise((resolve) => {
        grant = resolve;
      }),
  );
  prepareMatchAlerts();
  notifyMatchFound('cancelled', 'Alice', Date.now() + 15000);
  clearMatchAlert();
  grant('granted');
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(registration.showNotification).not.toHaveBeenCalled();
  expect(shown).toHaveLength(0);
});

it('retries a failed mobile worker registration on the next search', async () => {
  notifications();
  const { register, registration } = serviceWorker();
  register.mockRejectedValueOnce(new Error('Network unavailable'));
  prepareMatchAlerts();
  await vi.waitFor(() => expect(matchAlertStatus()).toBe('failed'));
  prepareMatchAlerts();
  notifyMatchFound('retry', 'Alice', Date.now() + 15000);
  await vi.waitFor(() => expect(registration.showNotification).toHaveBeenCalledOnce());
  expect(register).toHaveBeenCalledTimes(2);
});

it('explains iPhone Home Screen requirements and blocked permissions', () => {
  notifications('denied');
  expect(matchAlertStatus()).toBe('denied');
  vi.stubGlobal('navigator', { userAgent: 'iPhone', standalone: false });
  expect(matchAlertStatus()).toBe('home-screen');
  vi.stubGlobal('navigator', { userAgent: 'iPhone', standalone: true });
  expect(matchAlertStatus()).toBe('denied');
  vi.stubGlobal('isSecureContext', false);
  expect(matchAlertStatus()).toBe('insecure');
});
