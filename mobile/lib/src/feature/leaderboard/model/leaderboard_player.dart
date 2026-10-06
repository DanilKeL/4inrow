import 'package:equatable/equatable.dart';

final class LeaderboardPlayer extends Equatable {
  const new({
    required this.rank,
    required this.username,
    required this.elo,
    required this.games,
  });
  final int rank;
  final String username;
  final int elo;
  final int games;
  factory fromJson(Map<String, dynamic> json) => LeaderboardPlayer(
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    username: json['username']?.toString() ?? '',
    elo: (json['elo'] as num?)?.toInt() ?? 1000,
    games: (json['games'] as num?)?.toInt() ?? 0,
  );
  @override
  List<Object> get props => [rank, username, elo, games];
}
