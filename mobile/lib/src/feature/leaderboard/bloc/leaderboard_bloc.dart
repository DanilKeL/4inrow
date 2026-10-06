import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/leaderboard/bloc/leaderboard_event.dart';
import 'package:four3/src/feature/leaderboard/bloc/leaderboard_state.dart';
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
        emit(const LeaderboardState$Loading());
        try {
          emit(LeaderboardState$Ready(await _repository.load()));
        } on Exception catch (error) {
          emit(LeaderboardState$Failure(error.toString()));
        }
    }
  }
}
