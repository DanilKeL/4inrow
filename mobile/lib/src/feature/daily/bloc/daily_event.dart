import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/model/game_models.dart';

sealed class DailyEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => const <Object?>[];
}

final class DailyEvent$Load extends DailyEvent {
  const new();
}

final class DailyEvent$Flush extends DailyEvent {
  const new();
}

final class DailyEvent$AccountChanged extends DailyEvent {
  const new();
}

final class DailyEvent$SaveWin extends DailyEvent {
  const new({
    required this.challenge,
    required this.game,
    required this.ownerAtStart,
    required this.recordId,
  });

  final DailyChallenge challenge;
  final GameSnapshot game;
  final String? ownerAtStart;
  final String recordId;

  @override
  List<Object?> get props => <Object?>[challenge, game, ownerAtStart, recordId];
}
