// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createGame } from '../game/core';
import { OnlineClient } from './client';
import type { ServerEvent } from './protocol';

class FakeSocket {
  static OPEN = 1;
  static instances: FakeSocket[] = [];
  readyState = 0;
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onmessage: ((message: { data: string }) => void) | null = null;
  send = vi.fn();
  constructor(public url: string) {
    FakeSocket.instances.push(this);
  }
  open() {
    this.readyState = 1;
    this.onopen?.();
  }
  close() {
    this.readyState = 3;
    this.onclose?.();
  }
  emit(event: ServerEvent) {
    this.onmessage?.({ data: JSON.stringify(event) });
  }
}

const session: ServerEvent = {
  type: 'session',
  code: 'ABCDE',
  token: 'secret-resume-token',
  player: 1,
  snapshot: {
    code: 'ABCDE',
    game: createGame(),
    players: [{ name: 'Первый', connected: true }, null],
    revision: 0,
    round: 1,
    startedAt: null,
    finishedAt: null,
    rematch: [],
  },
};
const move = { type: 'move', x: 0, y: 0, revision: 0, round: 1 } as const;
let client: OnlineClient;
let handlers: {
  onEvent: ReturnType<typeof vi.fn>;
  onStatus: ReturnType<typeof vi.fn>;
  onFailure: ReturnType<typeof vi.fn>;
};
const latest = () => FakeSocket.instances.at(-1)!;
const connect = () => {
  client.connect({ type: 'create', name: 'Первый' }, handlers);
  latest().open();
};

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal('WebSocket', FakeSocket);
  FakeSocket.instances = [];
  window.sessionStorage.clear();
  client = new OnlineClient();
  handlers = { onEvent: vi.fn(), onStatus: vi.fn(), onFailure: vi.fn() };
});
afterEach(() => {
  client.disconnect();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe('online browser transport', () => {
  it('acknowledges matchmaking without saving a lobby until both accept', () => {
    client.connect({ type: 'quick_find', name: 'Игрок' }, handlers);
    latest().open();
    expect(JSON.parse(latest().send.mock.calls[0][0])).toEqual({
      type: 'quick_find',
      name: 'Игрок',
      searchId: expect.stringMatching(/^[a-f0-9]{32}$/),
    });
    latest().emit({ type: 'queue', status: 'searching' });
    expect(handlers.onStatus).toHaveBeenLastCalledWith('connected');
    expect(window.sessionStorage.getItem('four-cubed-online-session')).toBeNull();
    const offer = {
      type: 'match_found',
      matchId: 'a'.repeat(32),
      opponent: 'Другой',
      deadline: Date.now() + 15_000,
    } as const;
    latest().emit(offer);
    expect(handlers.onEvent).toHaveBeenLastCalledWith(offer);
    expect(client.send({ type: 'quick_accept', matchId: offer.matchId })).toBe(true);
    latest().emit(session);
    expect(client.restore(handlers)).toBe(true);
  });

  it('restores searching after a suspended mobile connection without user input', () => {
    client.connect({ type: 'quick_find', name: 'Игрок' }, handlers);
    latest().open();
    const request = latest().send.mock.calls[0][0];
    latest().emit({ type: 'queue', status: 'searching' });
    const visibility = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
    document.dispatchEvent(new Event('visibilitychange'));
    latest().close();
    vi.advanceTimersByTime(10 * 60_000);
    expect(handlers.onFailure).not.toHaveBeenCalled();
    expect(FakeSocket.instances).toHaveLength(1);
    visibility.mockReturnValue('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    latest().open();
    expect(latest().send).toHaveBeenCalledExactlyOnceWith(request);
    latest().emit({ type: 'queue', status: 'searching' });
    expect(handlers.onStatus).toHaveBeenLastCalledWith('connected');
    visibility.mockRestore();
  });

  it('replaces a stale OPEN mobile socket and ignores messages from it', () => {
    client.connect({ type: 'quick_find', name: 'Игрок' }, handlers);
    latest().open();
    latest().emit({ type: 'queue', status: 'searching' });
    const stale = latest();
    const visibility = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
    document.dispatchEvent(new Event('visibilitychange'));
    visibility.mockReturnValue('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    stale.emit({
      type: 'queue_removed',
      reason: 'expired',
      message: 'Время подтверждения истекло.',
    });
    expect(handlers.onStatus).toHaveBeenLastCalledWith('reconnecting');
    expect(FakeSocket.instances).toHaveLength(2);
    visibility.mockRestore();
  });

  it.each([false, true])(
    'requeues an expired suspended match even if its event arrives before visibilitychange (%s)',
    (alreadyVisible) => {
      client.connect({ type: 'quick_find', name: 'Игрок' }, handlers);
      latest().open();
      latest().emit({ type: 'queue', status: 'searching' });
      const visibility = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
      document.dispatchEvent(new Event('visibilitychange'));
      if (alreadyVisible) visibility.mockReturnValue('visible');
      latest().emit({
        type: 'queue_removed',
        reason: 'expired',
        message: 'Время подтверждения истекло.',
      });
      expect(client.isSearching).toBe(true);
      visibility.mockReturnValue('visible');
      document.dispatchEvent(new Event('visibilitychange'));
      latest().open();
      expect(JSON.parse(latest().send.mock.calls[0][0]).type).toBe('quick_find');
      expect(handlers.onFailure).not.toHaveBeenCalled();
      visibility.mockRestore();
    },
  );

  it('recovers a search after page restoration and forgets it on explicit cancellation', () => {
    client.connect({ type: 'quick_find', name: 'Игрок' }, handlers);
    latest().open();
    latest().emit({ type: 'queue', status: 'searching' });
    const saved = window.sessionStorage.getItem('four-cubed-online-search')!;
    client.disconnect();
    // The OS may discard the page without running any cleanup; storage survives that reload.
    window.sessionStorage.setItem('four-cubed-online-search', saved);
    client = new OnlineClient();
    expect(client.restore(handlers)).toBe(true);
    expect(client.isSearching).toBe(true);
    latest().open();
    expect(JSON.parse(latest().send.mock.calls[0][0]).searchId).toBe(JSON.parse(saved).searchId);
    client.disconnect();
    window.dispatchEvent(new Event('online'));
    document.dispatchEvent(new Event('visibilitychange'));
    expect(client.restore(handlers)).toBe(false);
    expect(FakeSocket.instances).toHaveLength(2);
  });

  it('waits for server acknowledgment and never queues moves', () => {
    connect();
    expect(latest().url).toBe(`ws://${window.location.host}/online`);
    expect(handlers.onStatus).toHaveBeenLastCalledWith('connecting');
    expect(client.send(move)).toBe(false);
    expect(latest().send).toHaveBeenCalledTimes(1);
    latest().emit(session);
    expect(handlers.onStatus).toHaveBeenLastCalledWith('connected');
    expect(client.send(move)).toBe(true);
    expect(latest().send).toHaveBeenLastCalledWith(JSON.stringify(move));
  });

  it('resumes with credentials after network loss without replaying moves', () => {
    connect();
    latest().emit(session);
    client.send(move);
    latest().close();
    expect(handlers.onStatus).toHaveBeenLastCalledWith('reconnecting');
    expect(client.send(move)).toBe(false);
    vi.advanceTimersByTime(500);
    latest().open();
    expect(latest().send).toHaveBeenCalledExactlyOnceWith(
      JSON.stringify({ type: 'resume', code: 'ABCDE', token: 'secret-resume-token' }),
    );
    latest().emit(session);
    expect(handlers.onStatus).toHaveBeenLastCalledWith('connected');
  });

  it('restores a session after a page reload and forgets it when leaving', () => {
    connect();
    latest().emit(session);
    client.disconnect();
    client = new OnlineClient();
    expect(client.restore(handlers)).toBe(true);
    latest().open();
    expect(latest().send).toHaveBeenCalledWith(
      JSON.stringify({ type: 'resume', code: 'ABCDE', token: 'secret-resume-token' }),
    );
    latest().emit(session);
    client.leave();
    expect(latest().send).toHaveBeenLastCalledWith(JSON.stringify({ type: 'leave' }));
    expect(client.restore(handlers)).toBe(false);
    vi.advanceTimersByTime(60_000);
    expect(FakeSocket.instances).toHaveLength(2);
  });

  it('restores from memory when browser session storage has been cleared', () => {
    connect();
    latest().emit(session);
    window.sessionStorage.clear();
    expect(client.restore(handlers)).toBe(true);
    latest().open();
    expect(latest().send).toHaveBeenCalledExactlyOnceWith(
      JSON.stringify({ type: 'resume', code: 'ABCDE', token: 'secret-resume-token' }),
    );
  });

  it('does not create duplicate lobbies when initial acknowledgment times out', () => {
    connect();
    vi.advanceTimersByTime(60_000);
    expect(FakeSocket.instances).toHaveLength(1);
    expect(handlers.onStatus).toHaveBeenLastCalledWith('error');
    expect(handlers.onFailure).toHaveBeenCalledOnce();
  });

  it('stops retrying and removes expired credentials on resume rejection', () => {
    connect();
    latest().emit(session);
    latest().close();
    vi.advanceTimersByTime(500);
    latest().open();
    const error = { type: 'error', code: 'not-found', message: 'Лобби не найдено.' } as const;
    latest().emit(error);
    expect(handlers.onEvent).toHaveBeenLastCalledWith(error);
    expect(client.restore(handlers)).toBe(false);
    vi.advanceTimersByTime(60_000);
    expect(FakeSocket.instances).toHaveLength(2);
  });

  it('keeps a session connected when the server rejects an illegal move', () => {
    connect();
    latest().emit(session);
    latest().emit({ type: 'error', code: 'turn', message: 'Сейчас ход соперника.' });
    expect(latest().readyState).toBe(1);
    expect(handlers.onStatus).toHaveBeenLastCalledWith('connected');
    expect(client.send(move)).toBe(true);
  });

  it('ignores late messages from a replaced connection', () => {
    connect();
    const old = latest();
    client.connect({ type: 'join', code: 'FGHIJ', name: 'Второй' }, handlers);
    old.emit(session);
    old.close();
    expect(handlers.onEvent).not.toHaveBeenCalled();
    expect(window.sessionStorage.getItem('four-cubed-online-session')).toBeNull();
    expect(handlers.onStatus).toHaveBeenLastCalledWith('connecting');
  });

  it('forgets credentials and stops reconnecting after lobby closure', () => {
    connect();
    latest().emit(session);
    const closed = { type: 'closed', message: 'Соперник покинул лобби.' } as const;
    latest().emit(closed);
    expect(handlers.onEvent).toHaveBeenLastCalledWith(closed);
    expect(client.restore(handlers)).toBe(false);
    vi.advanceTimersByTime(60_000);
    expect(FakeSocket.instances).toHaveLength(1);
  });

  it('bounds reconnection attempts and leaves credentials available for manual retry', () => {
    connect();
    latest().emit(session);
    latest().close();
    vi.advanceTimersByTime(6 * 60_000);
    expect(handlers.onStatus).toHaveBeenLastCalledWith('error');
    expect(handlers.onFailure).toHaveBeenCalledOnce();
    expect(FakeSocket.instances.length).toBeLessThan(30);
    expect(client.restore(handlers)).toBe(true);
  });

  it('ignores malformed stored sessions', () => {
    window.sessionStorage.setItem('four-cubed-online-session', '{broken');
    expect(client.restore(handlers)).toBe(false);
    window.sessionStorage.setItem(
      'four-cubed-online-session',
      JSON.stringify({ code: '12345', token: 'token', player: 1 }),
    );
    expect(client.restore(handlers)).toBe(false);
    expect(FakeSocket.instances).toHaveLength(0);
  });
});
