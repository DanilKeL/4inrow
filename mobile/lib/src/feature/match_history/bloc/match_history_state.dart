import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';

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
