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
  const new(this.players, {this.refreshing = false});

  final List<LeaderboardPlayer> players;
  final bool refreshing;

  @override
  List<Object> get props => [players, refreshing];
}

final class LeaderboardState$Failure extends LeaderboardState {
  const new(this.message);

  final String message;

  @override
  List<Object> get props => [message];
}
