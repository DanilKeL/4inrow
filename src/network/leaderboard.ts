export interface LeaderboardPlayer {
  rank: number;
  username: string;
  elo: number;
  games: number;
}

export interface LeaderboardResponse {
  players: LeaderboardPlayer[];
}
