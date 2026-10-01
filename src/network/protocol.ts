import type { GameState, Player } from '../game/core';

export interface OnlinePlayer {
  name: string;
  connected: boolean;
}

export interface LobbySnapshot {
  code: string;
  kind?: 'lobby' | 'quick';
  game: GameState;
  players: [OnlinePlayer, OnlinePlayer | null];
  revision: number;
  round: number;
  startedAt: number | null;
  finishedAt: number | null;
  rematch: Player[];
  ranking?: {
    rated: boolean;
    points: [number, number];
    changes?: [number, number];
    reason?: string;
  };
  turnDeadline?: number;
  endReason?: string;
  pause?: {
    used: boolean;
    totalMs: number;
    request?: { id: string; by: Player; expiresAt: number };
    startedAt?: number;
    endsAt?: number;
    ready?: Player[];
  };
}

export type ClientCommand =
  | { type: 'create'; name: string }
  | { type: 'join'; code: string; name: string }
  | { type: 'quick_find'; name: string; searchId?: string }
  | { type: 'quick_accept'; matchId: string }
  | { type: 'quick_decline'; matchId: string }
  | { type: 'quick_cancel' }
  | { type: 'resume'; code: string; token: string }
  | { type: 'move'; x: number; y: number; revision: number; round: number }
  | { type: 'rematch'; round: number }
  | { type: 'pause_request'; round: number }
  | { type: 'pause_answer'; round: number; requestId: string; accept: boolean }
  | { type: 'pause_ready'; round: number }
  | { type: 'leave' };

export type ServerEvent =
  | { type: 'session'; code: string; token: string; player: Player; snapshot: LobbySnapshot }
  | { type: 'state'; snapshot: LobbySnapshot }
  | { type: 'queue'; status: 'searching' }
  | {
      type: 'match_found';
      matchId: string;
      opponent: string;
      deadline: number;
      opponentRating?: number;
      rated?: boolean;
    }
  | { type: 'queue_removed'; message: string; reason?: 'expired' | 'cancelled' }
  | { type: 'error'; code: string; message: string }
  | { type: 'closed'; message: string };
