import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/daily/bloc/daily_event.dart';
import 'package:four3/src/feature/daily/bloc/daily_state.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/daily/domain/repository/daily_repository.dart';

final class DailyBloc extends Bloc<DailyEvent, DailyState> {
  new({required this._repository, required this._owner})
    : super(const DailyState()) {
    on<DailyEvent>(_onEvent, transformer: sequential());
  }

  final DailyRepository _repository;
  final String? Function() _owner;

  Future<void> _onEvent(DailyEvent event, Emitter<DailyState> emit) async {
    switch (event) {
      case DailyEvent$Load():
        await _load(emit);
      case DailyEvent$Flush():
        await _flush(emit);
      case DailyEvent$AccountChanged():
        emit(const DailyState());
        await _load(emit);
      case DailyEvent$SaveWin(
        :final challenge,
        :final game,
        :final ownerAtStart,
        :final recordId,
      ):
        final DailySubmission submission = await _repository.saveWin(
          id: recordId,
          challenge: challenge,
          game: game,
          owner: ownerAtStart,
          currentOwner: _owner(),
        );
        emit(
          state.copyWith(snapshot: submission.snapshot, submission: submission),
        );
    }
  }

  Future<void> _load(Emitter<DailyState> emit) async {
    emit(state.copyWith(loading: true, error: ''));
    try {
      final DailySnapshot snapshot = await _repository.load();
      if (snapshot.username != _owner()) {
        throw StateError('Account changed while loading daily challenge.');
      }
      emit(state.copyWith(snapshot: snapshot, loading: false, error: ''));
      add(const DailyEvent$Flush());
    } on RestClientException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    } on Object {
      emit(state.copyWith(loading: false, error: 'offline'));
    }
  }

  Future<void> _flush(Emitter<DailyState> emit) async {
    try {
      final DailyFlushResult result = await _repository.flush(_owner());
      final DailySubmission? current = state.submission;
      final DailySubmission? submission = current == null
          ? null
          : result.verifiedIds.contains(current.id)
          ? DailySubmission(
              id: current.id,
              status: DailySubmissionStatus.verified,
              snapshot: result.snapshot,
            )
          : result.failure?.id == current.id
          ? result.failure
          : current;
      if (result.snapshot != null || submission != current) {
        emit(state.copyWith(snapshot: result.snapshot, submission: submission));
      }
    } on Object {
      // The durable queue is retried on the next foreground/load event.
    }
  }
}
