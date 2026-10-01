export type MatchMode = 'local' | 'ai' | 'online';
export interface SavedMatch {
  id: string;
  title: string;
  date: number;
  names: [string, string];
  mode: MatchMode;
  elapsed: number;
  game: string;
  winner?: 1 | 2 | null;
  endReason?: string;
  ratingChange?: number;
  ratingAfter?: number;
}
export interface Statistics {
  total: number;
  wins: number;
  losses: number;
  draws: number;
}
export interface HistoryResponse {
  username: string;
  matches: SavedMatch[];
  statistics: Statistics;
  rating: { points: number; games: number };
}
