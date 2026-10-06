import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_status.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';

sealed class MatchmakingState extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class MatchmakingState$Initial extends MatchmakingState {
  const new();
}

final class MatchmakingState$Idle extends MatchmakingState {
  const new({this.message = '', this.notice});

  final String message;
  final MatchmakingNotice? notice;

  @override
  List<Object?> get props => [message, notice];
}

final class MatchmakingState$Connecting extends MatchmakingState {
  const new({this.reconnecting = false});

  final bool reconnecting;

  @override
  List<Object> get props => [reconnecting];
}

final class MatchmakingState$Searching extends MatchmakingState {
  const new();
}

final class MatchmakingState$Found extends MatchmakingState {
  const new({
    required this.matchId,
    required this.opponent,
    required this.deadline,
    required this.rated,
    this.rating,
    this.accepted = false,
  });

  final String matchId;
  final String opponent;
  final int deadline;
  final int? rating;
  final bool rated;
  final bool accepted;

  @override
  List<Object?> get props => [
    matchId,
    opponent,
    deadline,
    rating,
    rated,
    accepted,
  ];
}

final class MatchmakingState$Match extends MatchmakingState {
  const new({
    required this.snapshot,
    required this.player,
    required this.connection,
  });

  final OnlineMatchSnapshot snapshot;
  final Player player;
  final OnlineConnectionStatus connection;

  @override
  List<Object> get props => [snapshot, player, connection];
}

final class MatchmakingState$Failure extends MatchmakingState {
  const new(this.message, {this.failure});

  final String message;
  final MatchmakingFailure? failure;

  @override
  List<Object?> get props => [message, failure];
}
