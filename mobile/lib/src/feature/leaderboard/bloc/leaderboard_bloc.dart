import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/leaderboard/data/leaderboard_repository.dart';
import 'package:four3/src/feature/leaderboard/model/leaderboard_player.dart';

sealed class LeaderboardEvent extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class LeaderboardEvent$Load extends LeaderboardEvent {
  const new();
}

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

final class LeaderboardBloc extends Bloc<LeaderboardEvent, LeaderboardState> {
  new(this._repository) : super(const LeaderboardState$Initial()) {
    on<LeaderboardEvent>(_onEvent, transformer: sequential());
  }
  final LeaderboardRepository _repository;
  Future<void> _onEvent(
    LeaderboardEvent event,
    Emitter<LeaderboardState> emit,
  ) async {
    switch (event) {
      case LeaderboardEvent$Load():
        emit(const LeaderboardState$Loading());
        try {
          emit(LeaderboardState$Ready(await _repository.load()));
        } on Exception catch (error) {
          emit(LeaderboardState$Failure(error.toString()));
        }
    }
  }
}
