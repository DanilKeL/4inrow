import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/matchmaking/service/online_transport.dart';

sealed class MatchmakingEvent extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class MatchmakingEvent$Load extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Create extends MatchmakingEvent {
  const new(this.name);
  final String name;
  @override
  List<Object> get props => [name];
}

final class MatchmakingEvent$Join extends MatchmakingEvent {
  const new(this.name, this.code);
  final String name;
  final String code;
  @override
  List<Object> get props => [name, code];
}

final class MatchmakingEvent$Find extends MatchmakingEvent {
  const new(this.name);
  final String name;
  @override
  List<Object> get props => [name];
}

final class MatchmakingEvent$Accept extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Decline extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Cancel extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Move extends MatchmakingEvent {
  const new(this.x, this.y);
  final int x;
  final int y;
  @override
  List<Object> get props => [x, y];
}

final class MatchmakingEvent$Rematch extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Pause extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$PauseAnswer extends MatchmakingEvent {
  const new({required this.accept});
  final bool accept;
  @override
  List<Object> get props => [accept];
}

final class MatchmakingEvent$Ready extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Leave extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Foreground extends MatchmakingEvent {
  const new();
}

final class MatchmakingEvent$Transport extends MatchmakingEvent {
  const new(this.event);
  final OnlineTransportEvent event;
  @override
  List<Object> get props => [event];
}

sealed class MatchmakingState extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class MatchmakingState$Initial extends MatchmakingState {
  const new();
}

final class MatchmakingState$Idle extends MatchmakingState {
  const new({this.message = ''});
  final String message;
  @override
  List<Object> get props => [message];
}

final class MatchmakingState$Connecting extends MatchmakingState {
  const new();
}

final class MatchmakingState$Searching extends MatchmakingState {
  const new();
}

final class MatchmakingState$Found extends MatchmakingState {
  const new({
    required this.matchId,
    required this.opponent,
    required this.deadline,
    required this.rated,
    this.rating,
    this.accepted = false,
  });
  final String matchId;
  final String opponent;
  final int deadline;
  final int? rating;
  final bool rated;
  final bool accepted;
  @override
  List<Object?> get props => [
    matchId,
    opponent,
    deadline,
    rating,
    rated,
    accepted,
  ];
}

final class MatchmakingState$Match extends MatchmakingState {
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

final class MatchmakingState$Failure extends MatchmakingState {
  const new(this.message);
  final String message;
  @override
  List<Object> get props => [message];
}

final class MatchmakingBloc extends Bloc<MatchmakingEvent, MatchmakingState> {
  new({required this._transport}) : super(const MatchmakingState$Initial()) {
    on<MatchmakingEvent>(_onEvent, transformer: sequential());
    _subscription = _transport.events.listen(
      (event) => add(MatchmakingEvent$Transport(event)),
    );
  }

  final OnlineTransport _transport;
  late final StreamSubscription<OnlineTransportEvent> _subscription;
  Player? _player;
  OnlineMatchSnapshot? _snapshot;
  OnlineConnectionStatus _connection = OnlineConnectionStatus.idle;

  Future<void> _onEvent(
    MatchmakingEvent event,
    Emitter<MatchmakingState> emit,
  ) async {
    switch (event) {
      case MatchmakingEvent$Load():
        if (!await _transport.restore()) emit(const MatchmakingState$Idle());
      case MatchmakingEvent$Create(:final name):
        emit(const MatchmakingState$Connecting());
        await _transport.connect({'type': 'create', 'name': name});
      case MatchmakingEvent$Join(:final name, :final code):
        final String normalized = code.trim().toUpperCase();
        if (!RegExp(r'^[A-Z]{5}$').hasMatch(normalized)) {
          emit(
            const MatchmakingState$Failure('Введите пятибуквенный код лобби.'),
          );
          return;
        }
        emit(const MatchmakingState$Connecting());
        await _transport.connect({
          'type': 'join',
          'name': name,
          'code': normalized,
        });
      case MatchmakingEvent$Find(:final name):
        emit(const MatchmakingState$Connecting());
        await _transport.connect({'type': 'quick_find', 'name': name});
      case MatchmakingEvent$Accept():
        if (state case MatchmakingState$Found(:final matchId)) {
          if (_transport.send({'type': 'quick_accept', 'matchId': matchId})) {
            final value = state as MatchmakingState$Found;
            emit(
              MatchmakingState$Found(
                matchId: value.matchId,
                opponent: value.opponent,
                deadline: value.deadline,
                rating: value.rating,
                rated: value.rated,
                accepted: true,
              ),
            );
          }
        }
      case MatchmakingEvent$Decline():
        if (state case MatchmakingState$Found(:final matchId)) {
          _transport.send({'type': 'quick_decline', 'matchId': matchId});
        }
      case MatchmakingEvent$Cancel():
        _transport.send(const {'type': 'quick_cancel'});
        await _transport.disconnect(clearPersistence: true);
        emit(const MatchmakingState$Idle(message: 'Поиск отменён.'));
      case MatchmakingEvent$Move(:final x, :final y):
        final OnlineMatchSnapshot? snapshot = _snapshot;
        final Player? player = _player;
        if (snapshot == null ||
            player == null ||
            snapshot.game.status != GameStatus.playing ||
            snapshot.game.currentPlayer != player ||
            snapshot.pause?.endsAt != null) {
          return;
        }
        if (!_transport.send({
          'type': 'move',
          'x': x,
          'y': y,
          'revision': snapshot.revision,
          'round': snapshot.round,
        })) {
          emit(
            const MatchmakingState$Failure(
              'Нет связи с сервером. Ход не отправлен.',
            ),
          );
        }
      case MatchmakingEvent$Rematch():
        final OnlineMatchSnapshot? snapshot = _snapshot;
        if (snapshot != null) {
          _transport.send({'type': 'rematch', 'round': snapshot.round});
        }
      case MatchmakingEvent$Pause():
        final OnlineMatchSnapshot? snapshot = _snapshot;
        if (snapshot != null) {
          _transport.send({'type': 'pause_request', 'round': snapshot.round});
        }
      case MatchmakingEvent$PauseAnswer(:final accept):
        final OnlineMatchSnapshot? snapshot = _snapshot;
        final String? request = snapshot?.pause?.requestId;
        if (snapshot != null && request != null) {
          _transport.send({
            'type': 'pause_answer',
            'round': snapshot.round,
            'requestId': request,
            'accept': accept,
          });
        }
      case MatchmakingEvent$Ready():
        final OnlineMatchSnapshot? snapshot = _snapshot;
        if (snapshot != null) {
          _transport.send({'type': 'pause_ready', 'round': snapshot.round});
        }
      case MatchmakingEvent$Leave():
        await _transport.leave();
        _snapshot = null;
        _player = null;
        emit(const MatchmakingState$Idle());
      case MatchmakingEvent$Foreground():
        if (state is! MatchmakingState$Idle &&
            state is! MatchmakingState$Initial) {
          await _transport.wake();
        }
      case MatchmakingEvent$Transport(:final event):
        await _onTransport(event, emit);
    }
  }

  Future<void> _onTransport(
    OnlineTransportEvent event,
    Emitter<MatchmakingState> emit,
  ) async {
    switch (event) {
      case OnlineTransportEvent$Status(:final status):
        _connection = switch (status) {
          'connected' => OnlineConnectionStatus.connected,
          'reconnecting' => OnlineConnectionStatus.reconnecting,
          'error' => OnlineConnectionStatus.error,
          _ => OnlineConnectionStatus.connecting,
        };
        if (_snapshot != null && _player != null) {
          emit(
            MatchmakingState$Match(
              snapshot: _snapshot!,
              player: _player!,
              connection: _connection,
            ),
          );
        } else if (_connection == OnlineConnectionStatus.reconnecting) {
          emit(const MatchmakingState$Connecting());
        }
      case OnlineTransportEvent$Failure(:final message):
        emit(MatchmakingState$Failure(message));
      case OnlineTransportEvent$Message(:final json):
        switch (json['type']) {
          case 'session':
            _player = Player.fromValue(json['player']);
            _snapshot = OnlineMatchSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            );
            emit(
              MatchmakingState$Match(
                snapshot: _snapshot!,
                player: _player!,
                connection: OnlineConnectionStatus.connected,
              ),
            );
          case 'state':
            if (_player == null) return;
            _snapshot = OnlineMatchSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            );
            emit(
              MatchmakingState$Match(
                snapshot: _snapshot!,
                player: _player!,
                connection: _connection,
              ),
            );
          case 'queue':
            emit(const MatchmakingState$Searching());
          case 'match_found':
            emit(
              MatchmakingState$Found(
                matchId: json['matchId']?.toString() ?? '',
                opponent: json['opponent']?.toString() ?? 'Соперник',
                deadline: json['deadline'] is int ? json['deadline'] as int : 0,
                rating: json['opponentRating'] is int
                    ? json['opponentRating'] as int
                    : null,
                rated: json['rated'] == true,
              ),
            );
          case 'queue_removed':
            emit(
              MatchmakingState$Idle(
                message: json['message']?.toString() ?? 'Поиск завершён.',
              ),
            );
          case 'error':
            emit(
              MatchmakingState$Failure(
                json['message']?.toString() ?? 'Ошибка онлайн-игры.',
              ),
            );
          case 'closed':
            _snapshot = null;
            _player = null;
            emit(
              MatchmakingState$Failure(
                json['message']?.toString() ?? 'Лобби закрыто.',
              ),
            );
        }
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
