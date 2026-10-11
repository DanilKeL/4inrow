// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  initializeTelegram,
  syncTelegramViewport,
  telegramApp,
  telegramHaptic,
  type TelegramWebApp,
} from './bridge';

function mockApp(): TelegramWebApp {
  return {
    platform: 'android',
    initData: '',
    viewportStableHeight: 700,
    safeAreaInset: { top: 24, bottom: 16, left: 0, right: 0 },
    contentSafeAreaInset: { top: 48, bottom: 0, left: 0, right: 0 },
    ready: vi.fn(),
    expand: vi.fn(),
    requestFullscreen: vi.fn(),
    isVersionAtLeast: () => true,
    setHeaderColor: vi.fn(),
    setBackgroundColor: vi.fn(),
    setBottomBarColor: vi.fn(),
    disableVerticalSwipes: vi.fn(),
    enableClosingConfirmation: vi.fn(),
    disableClosingConfirmation: vi.fn(),
    onEvent: vi.fn(),
    offEvent: vi.fn(),
    BackButton: { show: vi.fn(), hide: vi.fn(), onClick: vi.fn(), offClick: vi.fn() },
    HapticFeedback: {
      impactOccurred: vi.fn(),
      notificationOccurred: vi.fn(),
      selectionChanged: vi.fn(),
    },
  };
}
afterEach(() => {
  delete window.Telegram;
  document.documentElement.removeAttribute('style');
  delete document.documentElement.dataset.telegram;
});
describe('Telegram bridge', () => {
  it('keeps ordinary browsers independent of Telegram', () => {
    expect(telegramApp()).toBeUndefined();
    initializeTelegram()();
    telegramHaptic('place');
    window.Telegram = { WebApp: { ...mockApp(), platform: 'unknown' } };
    expect(telegramApp()).toBeUndefined();
    expect(document.documentElement.dataset.telegram).toBeUndefined();
  });
  it('expands and updates combined device/content safe areas, removing listeners on cleanup', () => {
    const app = mockApp();
    window.Telegram = { WebApp: app };
    const stop = initializeTelegram();
    expect(app.ready).toHaveBeenCalledOnce();
    expect(app.expand).toHaveBeenCalledOnce();
    expect(app.requestFullscreen).toHaveBeenCalledOnce();
    expect(document.documentElement.style.getPropertyValue('--safe-area-inset-top')).toBe('72px');
    expect(document.documentElement.style.getPropertyValue('--four-viewport-height')).toBe('700px');
    app.viewportStableHeight = 480;
    syncTelegramViewport(app);
    expect(document.documentElement.style.getPropertyValue('--four-viewport-height')).toBe('480px');
    stop();
    expect(app.offEvent).toHaveBeenCalledTimes(5);
  });
  it('supports older clients without newer bridge APIs', () => {
    const app = mockApp();
    app.isVersionAtLeast = (version) => ['6.1', '6.2'].includes(version);
    window.Telegram = { WebApp: app };
    initializeTelegram();
    expect(app.setHeaderColor).toHaveBeenCalledWith('bg_color');
    expect(app.setBottomBarColor).not.toHaveBeenCalled();
    expect(app.disableVerticalSwipes).not.toHaveBeenCalled();
    expect(app.requestFullscreen).not.toHaveBeenCalled();
  });
  it('updates height and safe areas on fullscreen changes without requesting again', () => {
    const app = mockApp();
    window.Telegram = { WebApp: app };
    initializeTelegram();
    const listener = vi
      .mocked(app.onEvent)
      .mock.calls.find(([event]) => event === 'fullscreenChanged')?.[1];
    expect(listener).toBeTypeOf('function');
    app.viewportStableHeight = 844;
    app.contentSafeAreaInset!.top = 56;
    listener!();
    expect(document.documentElement.style.getPropertyValue('--four-viewport-height')).toBe('844px');
    expect(document.documentElement.style.getPropertyValue('--safe-area-inset-top')).toBe('80px');
    app.isFullscreen = false;
    listener!();
    expect(app.requestFullscreen).toHaveBeenCalledOnce();
  });
  it('keeps the expanded app usable when fullscreen throws or is unavailable', () => {
    const app = mockApp();
    app.requestFullscreen = vi.fn(() => {
      throw new Error('unsupported');
    });
    window.Telegram = { WebApp: app };
    expect(() => initializeTelegram()).not.toThrow();
    expect(app.ready).toHaveBeenCalledOnce();
    expect(app.expand).toHaveBeenCalledOnce();
    const failed = vi
      .mocked(app.onEvent)
      .mock.calls.find(([event]) => event === 'fullscreenFailed')?.[1];
    expect(() => failed!()).not.toThrow();
    app.requestFullscreen = undefined;
    expect(() => initializeTelegram()).not.toThrow();
  });
  it('does not request fullscreen when already fullscreen', () => {
    const app = mockApp();
    app.isFullscreen = true;
    window.Telegram = { WebApp: app };
    initializeTelegram();
    expect(app.requestFullscreen).not.toHaveBeenCalled();
  });
  it('maps moves, invalid columns and victories to native haptics', () => {
    const app = mockApp();
    window.Telegram = { WebApp: app };
    telegramHaptic('place');
    telegramHaptic('invalid');
    telegramHaptic('win');
    expect(app.HapticFeedback?.impactOccurred).toHaveBeenCalledWith('light');
    expect(app.HapticFeedback?.notificationOccurred).toHaveBeenCalledWith('error');
    expect(app.HapticFeedback?.notificationOccurred).toHaveBeenCalledWith('success');
  });
});
