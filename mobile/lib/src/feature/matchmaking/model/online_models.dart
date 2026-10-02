import 'dart:collection';

import 'package:equatable/equatable.dart';

import 'package:four3/src/feature/game/model/game_models.dart';

enum OnlineConnectionStatus { idle, connecting, connected, reconnecting, error }

final class OnlinePlayer extends Equatable {
  const new({required this.name, required this.connected});

  final String name;
  final bool connected;

  factory fromJson(Map<String, dynamic> json) => OnlinePlayer(
    name: json['name']?.toString() ?? 'Игрок',
    connected: json['connected'] == true,
  );

  @override
  List<Object> get props => [name, connected];
}

final class OnlineRanking extends Equatable {
  const new({
    required this.rated,
    required this.points,
    this.changes,
    this.reason,
  });

  final bool rated;
  final List<int> points;
  final List<int>? changes;
  final String? reason;

  factory fromJson(Map<String, dynamic> json) => OnlineRanking(
    rated: json['rated'] == true,
    points: _ints(json['points'], length: 2),
    changes: json['changes'] == null ? null : _ints(json['changes'], length: 2),
    reason: json['reason']?.toString(),
  );

  @override
  List<Object?> get props => [rated, points, changes, reason];
}

final class OnlinePause extends Equatable {
  const new({
    required this.used,
    required this.totalMs,
    this.requestId,
    this.requestedBy,
    this.requestExpiresAt,
    this.startedAt,
    this.endsAt,
    this.ready = const [],
  });

  final bool used;
  final int totalMs;
  final String? requestId;
  final Player? requestedBy;
  final int? requestExpiresAt;
  final int? startedAt;
  final int? endsAt;
  final List<Player> ready;

  factory fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? request =
        json['request'] is Map<String, dynamic>
        ? json['request'] as Map<String, dynamic>
        : null;
    return OnlinePause(
      used: json['used'] == true,
      totalMs: _integer(json['totalMs']),
      requestId: request?['id']?.toString(),
      requestedBy: _playerOrNull(request?['by']),
      requestExpiresAt: _nullableInteger(request?['expiresAt']),
      startedAt: _nullableInteger(json['startedAt']),
      endsAt: _nullableInteger(json['endsAt']),
      ready: (json['ready'] as List<dynamic>? ?? const [])
          .map(_playerOrNull)
          .whereType<Player>()
          .toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [
    used,
    totalMs,
    requestId,
    requestedBy,
    requestExpiresAt,
    startedAt,
    endsAt,
    ready,
  ];
}

final class OnlineMatchSnapshot extends Equatable {
  new({
    required this.code,
    required this.kind,
    required this.game,
    required List<OnlinePlayer?> players,
    required this.revision,
    required this.round,
    required this.startedAt,
    required this.finishedAt,
    required List<Player> rematch,
    this.ranking,
    this.turnDeadline,
    this.endReason,
    this.pause,
  }) : players = UnmodifiableListView(players),
       rematch = UnmodifiableListView(rematch);

  final String code;
  final String kind;
  final GameSnapshot game;
  final List<OnlinePlayer?> players;
  final int revision;
  final int round;
  final int? startedAt;
  final int? finishedAt;
  final List<Player> rematch;
  final OnlineRanking? ranking;
  final int? turnDeadline;
  final String? endReason;
  final OnlinePause? pause;

  factory fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawPlayers =
        json['players'] as List<dynamic>? ?? const [];
    return OnlineMatchSnapshot(
      code: json['code']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'lobby',
      game: _gameFromJson(_map(json['game'])),
      players: List<OnlinePlayer?>.generate(2, (index) {
        if (index >= rawPlayers.length || rawPlayers[index] == null) {
          return null;
        }
        return OnlinePlayer.fromJson(_map(rawPlayers[index]));
      }),
      revision: _integer(json['revision']),
      round: _integer(json['round'], fallback: 1),
      startedAt: _nullableInteger(json['startedAt']),
      finishedAt: _nullableInteger(json['finishedAt']),
      rematch: (json['rematch'] as List<dynamic>? ?? const [])
          .map(_playerOrNull)
          .whereType<Player>()
          .toList(growable: false),
      ranking: json['ranking'] is Map<String, dynamic>
          ? OnlineRanking.fromJson(json['ranking'] as Map<String, dynamic>)
          : null,
      turnDeadline: _nullableInteger(json['turnDeadline']),
      endReason: json['endReason']?.toString(),
      pause: json['pause'] is Map<String, dynamic>
          ? OnlinePause.fromJson(json['pause'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  List<Object?> get props => [
    code,
    kind,
    game,
    players,
    revision,
    round,
    startedAt,
    finishedAt,
    rematch,
    ranking,
    turnDeadline,
    endReason,
    pause,
  ];
}

GameSnapshot _gameFromJson(Map<String, dynamic> json) => GameSnapshot(
  board: _ints(json['board'], length: 125),
  heights: _ints(json['heights'], length: 25),
  currentPlayer: Player.fromValue(json['currentPlayer']),
  history: (json['history'] as List<dynamic>? ?? const [])
      .map((raw) {
        final Map<String, dynamic> move = _map(raw);
        return GameMove(
          x: _integer(move['x']),
          y: _integer(move['y']),
          z: _integer(move['z']),
          player: Player.fromValue(move['player']),
          index: _integer(move['index']),
        );
      })
      .toList(growable: false),
  status: switch (json['status']) {
    'won' => GameStatus.won,
    'draw' => GameStatus.draw,
    _ => GameStatus.playing,
  },
  winner: _playerOrNull(json['winner']),
  winningLines: (json['winningLines'] as List<dynamic>? ?? const [])
      .map(
        (rawLine) => (rawLine as List<dynamic>)
            .map((raw) {
              final Map<String, dynamic> value = _map(raw);
              return BoardPosition(
                _integer(value['x']),
                _integer(value['y']),
                _integer(value['z']),
              );
            })
            .toList(growable: false),
      )
      .toList(growable: false),
);

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid online snapshot');
  }
  return value;
}

int _integer(Object? value, {int fallback = 0}) =>
    value is int ? value : fallback;
int? _nullableInteger(Object? value) => value is int ? value : null;
Player? _playerOrNull(Object? value) => switch (value) {
  1 => Player.one,
  2 => Player.two,
  _ => null,
};

List<int> _ints(Object? value, {required int length}) {
  if (value is! List || value.length != length) {
    throw const FormatException('Invalid online snapshot array');
  }
  return value.map((item) => item is int ? item : 0).toList(growable: false);
}
