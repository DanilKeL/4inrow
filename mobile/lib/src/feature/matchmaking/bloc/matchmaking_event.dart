import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/matchmaking/service/online_transport.dart';

sealed class MatchmakingEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

sealed class MatchmakingEvent$Connection extends MatchmakingEvent {
  const new();
}

sealed class MatchmakingEvent$Sequential extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Load extends MatchmakingEvent$Connection {
  const new();
}

final class MatchmakingEvent$Create extends MatchmakingEvent$Connection {
  const new(this.name);

  final String name;

  @override
  List<Object> get props => [name];
}

final class MatchmakingEvent$Join extends MatchmakingEvent$Connection {
  const new(this.name, this.code);

  final String name;
  final String code;

  @override
  List<Object> get props => [name, code];
}

final class MatchmakingEvent$Find extends MatchmakingEvent$Connection {
  const new(this.name);

  final String name;

  @override
  List<Object> get props => [name];
}

final class MatchmakingEvent$Accept extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$Decline extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$Cancel extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$Move extends MatchmakingEvent$Sequential {
  const new(this.x, this.y);

  final int x;
  final int y;

  @override
  List<Object> get props => [x, y];
}

final class MatchmakingEvent$Rematch extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$Pause extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$PauseAnswer extends MatchmakingEvent$Sequential {
  const new({required this.accept});

  final bool accept;

  @override
  List<Object> get props => [accept];
}

final class MatchmakingEvent$Ready extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$Leave extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$Foreground extends MatchmakingEvent$Sequential {
  const new();
}

final class MatchmakingEvent$Transport extends MatchmakingEvent$Sequential {
  const new(this.event);

  final OnlineTransportEvent event;

  @override
  List<Object> get props => [event];
}
