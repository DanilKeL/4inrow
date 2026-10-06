import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';

sealed class GameState extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class GameState$Initial extends GameState {
  const new();
}

final class GameState$Ready extends GameState {
  const new(this.data);

  final GameViewData data;

  @override
  List<Object> get props => [data];
}

final class GameState$Failure extends GameState {
  const new(this.message);

  final String message;

  @override
  List<Object> get props => [message];
}
