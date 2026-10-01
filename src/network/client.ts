import type { Player } from '../game/core';
import type { ClientCommand, ServerEvent } from './protocol';
import { onlineEndpoint } from './endpoint';

export type ConnectionStatus = 'connecting' | 'connected' | 'reconnecting' | 'error';

export interface OnlineHandlers {
  onEvent: (event: ServerEvent) => void;
  onStatus: (status: ConnectionStatus) => void;
  onFailure: (message: string) => void;
}

type ConnectionCommand = Extract<
  ClientCommand,
  { type: 'create' | 'join' | 'resume' | 'quick_find' }
>;
interface Session {
  code: string;
  token: string;
  player?: Player;
}

const SESSION_KEY = 'four-cubed-online-session';
const SEARCH_KEY = 'four-cubed-online-search';
const HANDSHAKE_TIMEOUT = 8_000;
const RECONNECT_LIMIT = 5 * 60_000;

/** The server owns game state. Moves are never queued or replayed after reconnecting. */
export class OnlineClient {
  private socket: WebSocket | null = null;
  private handlers: OnlineHandlers | null = null;
  private session: Session | null = null;
  private generation = 0;
  private acknowledged = false;
  private retry = 0;
  private retryStartedAt: number | null = null;
  private handshakeTimer: ReturnType<typeof setTimeout> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private search: Extract<ClientCommand, { type: 'quick_find' }> | null = null;
  private hidden = false;

  get isSearching() {
    return this.search !== null;
  }

  private visibilityChanged = () => {
    if (document.visibilityState === 'hidden') {
      this.hidden = true;
      this.saveSearch();
    } else this.wake();
  };
  private wake = () => {
    if (document.visibilityState === 'hidden' || !this.handlers) return;
    const command = this.reconnectCommand();
    const shouldReconnect =
      this.hidden || !this.acknowledged || this.socket?.readyState !== WebSocket.OPEN;
    this.hidden = false;
    if (!command || !shouldReconnect) return;
    this.clearTimers();
    this.retryStartedAt = null;
    this.retry = 0;
    // A suspended mobile socket can still report OPEN even after the server has removed it.
    const previous = this.socket;
    this.socket = null;
    this.generation++;
    previous?.close();
    this.handlers.onStatus('reconnecting');
    this.open(command);
  };
  private reconnectCommand(): ConnectionCommand | null {
    return this.session
      ? { type: 'resume', code: this.session.code, token: this.session.token }
      : this.search;
  }

  connect(command: ConnectionCommand, handlers: OnlineHandlers): void {
    this.disconnect();
    this.handlers = handlers;
    this.retry = 0;
    this.retryStartedAt = null;
    this.hidden = document.visibilityState === 'hidden';
    document.addEventListener('visibilitychange', this.visibilityChanged);
    window.addEventListener('online', this.wake);
    window.addEventListener('pageshow', this.wake);
    if (command.type === 'quick_find') {
      this.search = {
        ...command,
        searchId:
          command.searchId ??
          Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) =>
            byte.toString(16).padStart(2, '0'),
          ).join(''),
      };
      command = this.search;
      this.saveSearch();
    }
    if (command.type === 'resume') {
      this.session = { code: command.code, token: command.token };
    } else {
      this.forgetSession();
    }
    handlers.onStatus('connecting');
    this.open(command);
  }

  restore(handlers: OnlineHandlers): boolean {
    const saved = this.session ?? this.readSession();
    if (!saved) {
      const search = this.search ?? this.readSearch();
      if (!search) return false;
      this.connect(search, handlers);
      return true;
    }
    this.connect({ type: 'resume', code: saved.code, token: saved.token }, handlers);
    return true;
  }

  send(command: ClientCommand): boolean {
    if (!this.acknowledged || this.socket?.readyState !== WebSocket.OPEN) return false;
    try {
      this.socket.send(JSON.stringify(command));
      return true;
    } catch {
      return false;
    }
  }

  leave(): void {
    this.send({ type: 'leave' });
    this.forgetSession();
    this.disconnect();
  }

  disconnect(): void {
    this.generation += 1;
    this.clearTimers();
    this.acknowledged = false;
    const socket = this.socket;
    this.socket = null;
    this.handlers = null;
    document.removeEventListener('visibilitychange', this.visibilityChanged);
    window.removeEventListener('online', this.wake);
    window.removeEventListener('pageshow', this.wake);
    this.forgetSearch();
    if (socket) socket.close();
  }

  private open(command: ConnectionCommand): void {
    const generation = ++this.generation;
    this.acknowledged = false;
    let socket: WebSocket;
    try {
      socket = new WebSocket(onlineEndpoint(window.location));
    } catch {
      this.connectionLost();
      return;
    }
    this.socket = socket;
    const isCurrent = () => this.generation === generation && this.socket === socket;
    this.handshakeTimer = setTimeout(() => {
      if (!isCurrent()) return;
      this.generation += 1;
      this.socket = null;
      socket.close();
      this.connectionLost();
    }, HANDSHAKE_TIMEOUT);

    socket.onopen = () => {
      if (!isCurrent()) return;
      socket.send(JSON.stringify(command));
    };
    socket.onmessage = (message) => {
      if (!isCurrent()) return;
      let event: ServerEvent;
      try {
        event = JSON.parse(String(message.data)) as ServerEvent;
      } catch {
        this.fail('Сервер прислал некорректный ответ. Попробуйте подключиться снова.');
        return;
      }
      if (
        !event ||
        !['session', 'state', 'queue', 'match_found', 'queue_removed', 'error', 'closed'].includes(
          event.type,
        )
      ) {
        this.fail('Сервер прислал некорректный ответ. Попробуйте подключиться снова.');
        return;
      }
      if (event.type === 'session') {
        this.clearTimers();
        this.forgetSearch();
        this.session = { code: event.code, token: event.token, player: event.player };
        this.saveSession();
        this.acknowledged = true;
        this.retry = 0;
        this.retryStartedAt = null;
        this.handlers?.onEvent(event);
        if (isCurrent()) this.handlers?.onStatus('connected');
        return;
      }
      if (event.type === 'queue') {
        this.clearTimers();
        this.retry = 0;
        this.retryStartedAt = null;
        this.saveSearch();
        this.acknowledged = true;
        this.handlers?.onEvent(event);
        if (isCurrent()) this.handlers?.onStatus('connected');
        return;
      }
      if (event.type === 'queue_removed') {
        if (
          this.search &&
          event.reason === 'expired' &&
          (this.hidden || document.visibilityState === 'hidden')
        ) {
          this.clearTimers();
          this.acknowledged = false;
          this.hidden = true;
          this.handlers?.onStatus('reconnecting');
          if (document.visibilityState !== 'hidden') this.wake();
          return;
        }
        const handlers = this.handlers;
        this.disconnect();
        handlers?.onEvent(event);
        handlers?.onStatus('error');
        return;
      }
      if (event.type === 'closed' || (event.type === 'error' && !this.acknowledged)) {
        const handlers = this.handlers;
        this.forgetSession();
        this.disconnect();
        handlers?.onEvent(event);
        handlers?.onStatus('error');
        return;
      }
      this.handlers?.onEvent(event);
    };
    // Browsers follow an error with a close event; retry once from that close.
    socket.onerror = () => {};
    socket.onclose = () => {
      if (!isCurrent()) return;
      this.socket = null;
      this.clearTimers();
      this.connectionLost();
    };
  }

  private connectionLost(): void {
    this.acknowledged = false;
    if (!this.handlers) return;
    if (!this.reconnectCommand()) {
      this.fail('Не удалось подключиться к серверу. Проверьте интернет и попробуйте снова.');
      return;
    }
    this.handlers.onStatus('reconnecting');
    if (document.visibilityState === 'hidden') {
      this.hidden = true;
      return;
    }
    this.retryStartedAt ??= Date.now();
    const remaining = RECONNECT_LIMIT - (Date.now() - this.retryStartedAt);
    if (remaining <= 0) {
      this.fail('Связь с сервером потеряна. Обновите страницу, чтобы вернуться в лобби.');
      return;
    }
    const delay = Math.min(500 * 2 ** Math.min(this.retry++, 5), 10_000, remaining);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      const command = this.reconnectCommand();
      if (!command || !this.handlers) return;
      if (Date.now() - this.retryStartedAt! >= RECONNECT_LIMIT) {
        this.fail('Связь с сервером потеряна. Обновите страницу, чтобы вернуться в лобби.');
        return;
      }
      this.open(command);
    }, delay);
  }

  private fail(message: string): void {
    const handlers = this.handlers;
    this.disconnect();
    handlers?.onStatus('error');
    handlers?.onFailure(message);
  }

  private clearTimers(): void {
    if (this.handshakeTimer !== null) clearTimeout(this.handshakeTimer);
    if (this.retryTimer !== null) clearTimeout(this.retryTimer);
    this.handshakeTimer = null;
    this.retryTimer = null;
  }

  private saveSession(): void {
    try {
      window.sessionStorage.setItem(SESSION_KEY, JSON.stringify(this.session));
    } catch {
      // Reconnect within this page still works when browser storage is disabled.
    }
  }
  private saveSearch(): void {
    if (!this.search) return;
    try {
      window.sessionStorage.setItem(
        SEARCH_KEY,
        JSON.stringify({ ...this.search, savedAt: Date.now() }),
      );
    } catch {
      /* Memory still supports reconnect. */
    }
  }
  private forgetSearch(): void {
    this.search = null;
    try {
      window.sessionStorage.removeItem(SEARCH_KEY);
    } catch {
      /* Storage may be unavailable. */
    }
  }
  private readSearch(): Extract<ClientCommand, { type: 'quick_find' }> | null {
    try {
      const saved = JSON.parse(window.sessionStorage.getItem(SEARCH_KEY) ?? 'null');
      if (
        saved?.type === 'quick_find' &&
        typeof saved.name === 'string' &&
        saved.name.length <= 200 &&
        /^[a-f0-9]{32}$/.test(saved.searchId) &&
        typeof saved.savedAt === 'number' &&
        Date.now() - saved.savedAt < RECONNECT_LIMIT
      )
        return { type: 'quick_find', name: saved.name, searchId: saved.searchId };
    } catch {
      /* Ignore invalid searches. */
    }
    return null;
  }

  private forgetSession(): void {
    this.session = null;
    try {
      window.sessionStorage.removeItem(SESSION_KEY);
    } catch {
      // Storage may be unavailable in private or restricted browser contexts.
    }
  }

  private readSession(): Session | null {
    try {
      const saved = JSON.parse(
        window.sessionStorage.getItem(SESSION_KEY) ?? 'null',
      ) as Session | null;
      if (
        saved &&
        /^[A-Z]{5}$/.test(saved.code) &&
        typeof saved.token === 'string' &&
        saved.token.length > 0 &&
        (saved.player === 1 || saved.player === 2)
      ) {
        return saved;
      }
    } catch {
      // Invalid or inaccessible saved sessions simply do not restore.
    }
    return null;
  }
}

export const onlineClient = new OnlineClient();
