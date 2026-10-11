/** Native presentation and raw launch data. Telegram identity is verified only on the server. */
interface Insets {
  top: number;
  bottom: number;
  left: number;
  right: number;
}
interface NativeButton {
  show(): void;
  hide(): void;
  onClick(callback: () => void): void;
  offClick(callback: () => void): void;
}
export interface TelegramWebApp {
  platform: string;
  initData: string;
  viewportStableHeight: number;
  safeAreaInset?: Insets;
  contentSafeAreaInset?: Insets;
  isFullscreen?: boolean;
  ready(): void;
  expand(): void;
  requestFullscreen?(): void;
  isVersionAtLeast(version: string): boolean;
  setHeaderColor(color: string): void;
  setBackgroundColor(color: string): void;
  setBottomBarColor?(color: string): void;
  disableVerticalSwipes?(): void;
  enableClosingConfirmation(): void;
  disableClosingConfirmation(): void;
  onEvent(event: string, callback: () => void): void;
  offEvent(event: string, callback: () => void): void;
  BackButton: NativeButton;
  SettingsButton?: NativeButton;
  HapticFeedback?: {
    impactOccurred(style: 'light'): void;
    notificationOccurred(type: 'error' | 'success'): void;
    selectionChanged(): void;
  };
}
declare global {
  interface Window {
    Telegram?: { WebApp?: TelegramWebApp };
  }
}

export function telegramApp(): TelegramWebApp | undefined {
  const app = window.Telegram?.WebApp;
  return app && app.platform !== 'unknown' ? app : undefined;
}

export function syncTelegramViewport(app: TelegramWebApp) {
  const root = document.documentElement;
  if (app.viewportStableHeight > 0)
    root.style.setProperty('--four-viewport-height', `${app.viewportStableHeight}px`);
  for (const side of ['top', 'bottom', 'left', 'right'] as const) {
    const inset =
      Math.max(0, app.safeAreaInset?.[side] ?? 0) +
      Math.max(0, app.contentSafeAreaInset?.[side] ?? 0);
    root.style.setProperty(`--safe-area-inset-${side}`, `${inset}px`);
  }
}

export function initializeTelegram(): () => void {
  const app = telegramApp();
  if (!app) return () => {};
  document.documentElement.dataset.telegram = 'true';
  const sync = () => syncTelegramViewport(app);
  sync();
  app.expand();
  if (app.isVersionAtLeast('6.1')) {
    app.setBackgroundColor('#f3f2ee');
    app.setHeaderColor(app.isVersionAtLeast('6.9') ? '#f3f2ee' : 'bg_color');
  }
  if (app.isVersionAtLeast('7.10')) app.setBottomBarColor?.('#f3f2ee');
  // Rotation of the 3D board must not minimize the Mini App.
  if (app.isVersionAtLeast('7.7')) app.disableVerticalSwipes?.();
  const events = ['viewportChanged', 'safeAreaChanged', 'contentSafeAreaChanged'];
  if (app.isVersionAtLeast('8.0')) events.push('fullscreenChanged', 'fullscreenFailed');
  events.forEach((event) => app.onEvent(event, sync));
  app.ready();
  if (app.isVersionAtLeast('8.0') && app.requestFullscreen && !app.isFullscreen) {
    try {
      // Request once at launch; let the user leave fullscreen without forcing it back.
      app.requestFullscreen();
    } catch {
      // Clients that cannot enter fullscreen keep the expanded layout.
    }
    sync();
  }
  return () => events.forEach((event) => app.offEvent(event, sync));
}

export async function loadTelegramSDK(): Promise<void> {
  const launch = new URLSearchParams(window.location.hash.slice(1));
  const preview = new URLSearchParams(window.location.search).has('telegram');
  if (
    window.Telegram ||
    (!launch.has('tgWebAppPlatform') && !launch.has('tgWebAppData') && !preview)
  )
    return;
  // Load only in Telegram: normal browser/offline starts do not depend on its CDN.
  await new Promise<void>((resolve) => {
    const script = document.createElement('script');
    script.src = 'https://telegram.org/js/telegram-web-app.js?64';
    const timer = window.setTimeout(resolve, 4000);
    const done = () => {
      window.clearTimeout(timer);
      resolve();
    };
    script.onload = done;
    script.onerror = done;
    document.head.append(script);
  });
}

export function telegramHaptic(kind: 'place' | 'invalid' | 'win' | 'click' | 'match') {
  const app = telegramApp();
  if (!app?.isVersionAtLeast('6.1')) return;
  const feedback = app.HapticFeedback;
  if (kind === 'place') feedback?.impactOccurred('light');
  else if (kind === 'win' || kind === 'match') feedback?.notificationOccurred('success');
  else if (kind === 'invalid') feedback?.notificationOccurred('error');
  else feedback?.selectionChanged();
}
