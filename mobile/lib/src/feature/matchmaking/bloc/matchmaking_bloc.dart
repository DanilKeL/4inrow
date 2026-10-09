import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_event.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_state.dart';
import 'package:four3/src/feature/matchmaking/bloc/matchmaking_status.dart';
import 'package:four3/src/feature/matchmaking/model/online_models.dart';
import 'package:four3/src/feature/matchmaking/service/online_transport.dart';

final class MatchmakingBloc extends Bloc<MatchmakingEvent, MatchmakingState> {
  new({required this._transport}) : super(const MatchmakingState$Initial()) {
    on<MatchmakingEvent$Connection>(_onConnection, transformer: restartable());
    on<MatchmakingEvent$Sequential>(_onSequential, transformer: sequential());
    _subscription = _transport.events.listen(
      (event) => add(MatchmakingEvent$Transport(event)),
    );
  }

  final OnlineTransportClient _transport;
  late final StreamSubscription<OnlineTransportEvent> _subscription;
  Player? _player;
  OnlineMatchSnapshot? _snapshot;
  OnlineConnectionStatus _connection = OnlineConnectionStatus.idle;

  Future<void> _onConnection(
    MatchmakingEvent$Connection event,
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
            const MatchmakingState$Failure(
              '',
              failure: MatchmakingFailure.invalidCode,
            ),
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
    }
  }

  Future<void> _onSequential(
    MatchmakingEvent$Sequential event,
    Emitter<MatchmakingState> emit,
  ) async {
    switch (event) {
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
        emit(
          const MatchmakingState$Idle(
            notice: MatchmakingNotice.searchCancelled,
          ),
        );
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
              '',
              failure: MatchmakingFailure.moveNotSent,
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
          emit(const MatchmakingState$Connecting(reconnecting: true));
        }
      case OnlineTransportEvent$Failure(:final message, :final failure):
        emit(
          MatchmakingState$Failure(
            message,
            failure: switch (failure) {
              OnlineTransportFailure.invalidResponse =>
                MatchmakingFailure.invalidServerResponse,
              OnlineTransportFailure.connectionLost =>
                MatchmakingFailure.connectionLost,
              null => null,
            },
          ),
        );
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
                opponent: json['opponent']?.toString() ?? 'Opponent',
                deadline: json['deadline'] is int ? json['deadline'] as int : 0,
                rating: json['opponentRating'] is int
                    ? json['opponentRating'] as int
                    : null,
                rated: json['rated'] == true,
              ),
            );
          case 'queue_removed':
            emit(
              MatchmakingState$Idle(message: json['message']?.toString() ?? ''),
            );
          case 'error':
            emit(
              MatchmakingState$Failure(
                json['message']?.toString() ?? '',
                failure: json['message'] == null
                    ? MatchmakingFailure.generic
                    : null,
              ),
            );
          case 'closed':
            _snapshot = null;
            _player = null;
            emit(
              MatchmakingState$Failure(
                json['message']?.toString() ?? '',
                failure: MatchmakingFailure.lobbyClosed,
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
