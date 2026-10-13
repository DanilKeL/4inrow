import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/leaderboard/bloc/leaderboard_event.dart';
import 'package:four3/src/feature/leaderboard/bloc/leaderboard_state.dart';
import 'package:four3/src/feature/leaderboard/domain/model/leaderboard_player.dart';
import 'package:four3/src/feature/leaderboard/domain/repository/leaderboard_repository.dart';

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
        final List<LeaderboardPlayer>? existing = switch (state) {
          LeaderboardState$Ready(:final List<LeaderboardPlayer> players) =>
            players,
          _ => null,
        };
        if (existing == null) {
          emit(const LeaderboardState$Loading());
        } else {
          emit(LeaderboardState$Ready(existing, refreshing: true));
        }
        try {
          emit(LeaderboardState$Ready(await _repository.load()));
        } on Exception catch (error) {
          if (existing == null) {
            emit(LeaderboardState$Failure(error.toString()));
          } else {
            emit(LeaderboardState$Ready(existing));
          }
        }
    }
  }
}
