export type AnalyticsMode = 'ai' | 'local' | 'level' | 'ranked' | 'lobby';
export type AnalyticsDevice = 'desktop' | 'mobile' | 'tablet';
export type AnalyticsResult = 'win' | 'loss' | 'draw';
export interface AnalyticsFilter {
  from: string;
  to: string;
  mode: AnalyticsMode | 'all';
  device: AnalyticsDevice | 'all';
}
export interface AnalyticsDashboard {
  generatedAt: number;
  collectionStartedAt: number;
  filter: AnalyticsFilter;
  summary: {
    visitors: number;
    sessions: number;
    returningVisitors: number;
    activeNow: number;
    averageActiveSeconds: number;
    started: number;
    completed: number;
    abandoned: number;
    unfinished: number;
    averageGameSeconds: number;
    registeredPlayers: number;
    guestPlayers: number;
    previousVisitors: number;
    previousStarted: number;
  };
  accounts: { total: number; new: number; verified: number; blocked: number };
  daily: {
    date: string;
    visitors: number;
    sessions: number;
    started: number;
    completed: number;
    registrations: number;
  }[];
  modes: {
    mode: AnalyticsMode;
    started: number;
    completed: number;
    abandoned: number;
    averageSeconds: number;
  }[];
  bots: {
    difficulty: string;
    started: number;
    completed: number;
    wins: number;
    losses: number;
    draws: number;
    averageMoves: number;
    averageSeconds: number;
  }[];
  devices: { name: string; sessions: number; visitors: number }[];
  browsers: { name: string; sessions: number; visitors: number }[];
  sources: { name: string; sessions: number; visitors: number }[];
  players: {
    username: string;
    games: number;
    completed: number;
    wins: number;
    losses: number;
    draws: number;
    ai: number;
    local: number;
    level: number;
    ranked: number;
    lobby: number;
    favoriteMode: AnalyticsMode;
    lastPlayedAt: number;
    bots: { difficulty: string; wins: number; losses: number; draws: number }[];
  }[];
  levels: {
    level: number;
    started: number;
    completed: number;
    wins: number;
    losses: number;
    bestMoves: number | null;
  }[];
}
