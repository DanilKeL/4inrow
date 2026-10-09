import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';

sealed class GameEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class GameEvent$Load extends GameEvent {
  const new();
}

final class GameEvent$Start extends GameEvent {
  const new({
    required this.mode,
    required this.difficulty,
    required this.names,
  });

  final GameMode mode;
  final Difficulty difficulty;
  final List<String> names;

  @override
  List<Object> get props => [mode, difficulty, names];
}

final class GameEvent$StartLevel extends GameEvent {
  const new(this.id);

  final int id;

  @override
  List<Object> get props => [id];
}

final class GameEvent$StartDaily extends GameEvent {
  const new(this.challenge);

  final DailyChallenge challenge;

  @override
  List<Object> get props => <Object>[challenge];
}

final class GameEvent$ResumeSaved extends GameEvent {
  const new();
}

final class GameEvent$DiscardSaved extends GameEvent {
  const new();
}

final class GameEvent$Persist extends GameEvent {
  const new();
}

final class GameEvent$MakeMove extends GameEvent {
  const new(this.x, this.y);

  final int x;
  final int y;

  @override
  List<Object> get props => [x, y];
}

final class GameEvent$Settle extends GameEvent {
  const new();
}

final class GameEvent$AiCompleted extends GameEvent {
  const new(this.move, this.expectedMoves, [this.error]);

  final MoveCandidate? move;
  final int expectedMoves;
  final Object? error;

  @override
  List<Object?> get props => [move, expectedMoves, error];
}

final class GameEvent$Pause extends GameEvent {
  const new();
}

final class GameEvent$Resume extends GameEvent {
  const new();
}

final class GameEvent$Undo extends GameEvent {
  const new();
}

final class GameEvent$Restart extends GameEvent {
  const new();
}

final class GameEvent$Menu extends GameEvent {
  const new();
}

final class GameEvent$Tick extends GameEvent {
  const new();
}

final class GameEvent$ToggleXray extends GameEvent {
  const new();
}

final class GameEvent$ToggleLayer extends GameEvent {
  const new(this.layer);

  final int layer;

  @override
  List<Object> get props => [layer];
}

final class GameEvent$ShowAllLayers extends GameEvent {
  const new();
}

final class GameEvent$View extends GameEvent {
  const new(this.view);

  final CameraView view;

  @override
  List<Object> get props => [view];
}

final class GameEvent$OpenReplay extends GameEvent {
  const new();
}

final class GameEvent$SeekReplay extends GameEvent {
  const new(this.index);

  final int index;

  @override
  List<Object> get props => [index];
}

final class GameEvent$CloseReplay extends GameEvent {
  const new();
}

final class GameEvent$ReplaySaved extends GameEvent {
  const new({required this.snapshot, required this.names});

  final GameSnapshot snapshot;
  final List<String> names;

  @override
  List<Object> get props => [snapshot, names];
}

final class GameEvent$OnlineSnapshot extends GameEvent {
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

final class GameEvent$OnlineFailure extends GameEvent {
  const new(this.message, {this.connectionError = false});

  final String message;
  final bool connectionError;

  @override
  List<Object> get props => [message, connectionError];
}
