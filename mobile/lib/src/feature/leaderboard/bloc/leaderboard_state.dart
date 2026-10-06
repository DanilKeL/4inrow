import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/leaderboard/domain/model/leaderboard_player.dart';

sealed class LeaderboardState extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class LeaderboardState$Initial extends LeaderboardState {
  const new();
}

final class LeaderboardState$Loading extends LeaderboardState {
  const new();
}

final class LeaderboardState$Ready extends LeaderboardState {
  const new(this.players);

  final List<LeaderboardPlayer> players;

  @override
  List<Object> get props => [players];
}

final class LeaderboardState$Failure extends LeaderboardState {
  const new(this.message);

  final String message;

  @override
  List<Object> get props => [message];
}
