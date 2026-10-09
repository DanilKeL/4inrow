import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_event.dart';
import 'package:four3/src/feature/match_history/bloc/match_history_state.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';
import 'package:four3/src/feature/match_history/domain/repository/match_history_repository.dart';

final class MatchHistoryBloc
    extends Bloc<MatchHistoryEvent, MatchHistoryState> {
  new({required this._repository, required this._owner})
    : super(const MatchHistoryState$Initial()) {
    on<MatchHistoryEvent>(_onEvent, transformer: sequential());
  }
  final MatchHistoryRepository _repository;
  final String? Function() _owner;
  final Set<String> _saved = {};

  Future<void> _onEvent(
    MatchHistoryEvent event,
    Emitter<MatchHistoryState> emit,
  ) async {
    switch (event) {
      case MatchHistoryEvent$Load():
        await _load(emit);
      case MatchHistoryEvent$Flush():
        await _flush(emit);
      case MatchHistoryEvent$Save(:final data):
        await _save(emit, data);
      case MatchHistoryEvent$Rename(:final id, :final title):
        await _mutate(emit, () => _repository.rename(_owner()!, id, title));
      case MatchHistoryEvent$Remove(:final id):
        await _mutate(emit, () => _repository.remove(_owner()!, id));
    }
  }

  Future<void> _load(Emitter<MatchHistoryState> emit) async {
    if (_owner() == null) {
      emit(const MatchHistoryState$Guest());
      return;
    }
    emit(const MatchHistoryState$Loading());
    await _mutate(emit, () => _repository.load(_owner()!));
  }

  Future<void> _save(Emitter<MatchHistoryState> emit, GameViewData data) async {
    final String? owner = data.accountAtStart;
    if (owner == null ||
        owner != _owner() ||
        data.mode == GameMode.online ||
        data.mode == GameMode.level ||
        data.mode == GameMode.daily ||
        data.snapshot.status == GameStatus.playing) {
      return;
    }
    final String id = data.recordId.isEmpty
        ? 'local-${DateTime.now().millisecondsSinceEpoch}'
        : data.recordId;
    if (!_saved.add(id)) return;
    try {
      final MatchHistorySnapshot? snapshot = await _repository.save(
        owner,
        _owner(),
        id,
        data,
      );
      if (snapshot != null) emit(MatchHistoryState$Ready(snapshot));
    } on Exception {
      _saved.remove(id);
    }
  }

  Future<void> _flush(Emitter<MatchHistoryState> emit) async {
    try {
      final MatchHistorySnapshot? snapshot = await _repository.flush(_owner());
      if (snapshot != null) emit(MatchHistoryState$Ready(snapshot));
    } on Exception {
      // The durable outbox remains available for the next retry.
    }
  }

  Future<void> _mutate(
    Emitter<MatchHistoryState> emit,
    Future<MatchHistorySnapshot> Function() action,
  ) async {
    if (_owner() == null) {
      emit(const MatchHistoryState$Guest());
      return;
    }
    try {
      emit(MatchHistoryState$Ready(await action()));
    } on Exception catch (error) {
      emit(MatchHistoryState$Failure(error.toString()));
    }
  }
}
