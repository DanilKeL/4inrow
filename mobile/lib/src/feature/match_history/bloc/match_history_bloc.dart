import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/match_history/data/match_history_repository.dart';
import 'package:four3/src/feature/match_history/model/match_history_models.dart';

sealed class MatchHistoryEvent extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class MatchHistoryEvent$Load extends MatchHistoryEvent {
  const new();
}

final class MatchHistoryEvent$Save extends MatchHistoryEvent {
  const new(this.data);
  final GameViewData data;
  @override
  List<Object> get props => [data];
}

final class MatchHistoryEvent$Rename extends MatchHistoryEvent {
  const new(this.id, this.title);
  final String id;
  final String title;
  @override
  List<Object> get props => [id, title];
}

final class MatchHistoryEvent$Remove extends MatchHistoryEvent {
  const new(this.id);
  final String id;
  @override
  List<Object> get props => [id];
}

sealed class MatchHistoryState extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class MatchHistoryState$Initial extends MatchHistoryState {
  const new();
}

final class MatchHistoryState$Loading extends MatchHistoryState {
  const new();
}

final class MatchHistoryState$Ready extends MatchHistoryState {
  const new(this.data);
  final MatchHistorySnapshot data;
  @override
  List<Object> get props => [data];
}

final class MatchHistoryState$Guest extends MatchHistoryState {
  const new();
}

final class MatchHistoryState$Failure extends MatchHistoryState {
  const new(this.message);
  final String message;
  @override
  List<Object> get props => [message];
}

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
    await _mutate(emit, _repository.load);
  }

  Future<void> _save(Emitter<MatchHistoryState> emit, GameViewData data) async {
    final String? owner = _owner();
    if (owner == null ||
        data.mode == GameMode.online ||
        data.mode == GameMode.level ||
        data.snapshot.status == GameStatus.playing) {
      return;
    }
    final signature =
        '${data.mode.name}-${data.snapshot.history.map((m) => '${m.x}${m.y}').join()}';
    if (!_saved.add(signature)) return;
    final id = 'local-${DateTime.now().millisecondsSinceEpoch}';
    try {
      emit(MatchHistoryState$Ready(await _repository.save(owner, id, data)));
    } on Exception {
      _saved.remove(signature);
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
