import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';

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
