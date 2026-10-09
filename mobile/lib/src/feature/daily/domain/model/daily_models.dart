import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

final class DailyChallenge extends Equatable {
  const new({
    required this.id,
    required this.date,
    required this.preset,
    required this.expiresAt,
  });

  factory fromJson(Map<String, dynamic> json) {
    final String date = json['date']?.toString() ?? '';
    final Object? rawPreset = json['preset'];
    if (json['version'] != 1 ||
        json['id'] != 'daily-1-$date' ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        rawPreset is! List ||
        rawPreset.length < 12 ||
        rawPreset.length > 100 ||
        rawPreset.length.isOdd ||
        json['expiresAt'] is! num) {
      throw const FormatException('Invalid daily challenge');
    }
    final List<int> dateParts = date.split('-').map(int.parse).toList();
    final DateTime midnight = DateTime.utc(
      dateParts[0],
      dateParts[1],
      dateParts[2],
    );
    final num rawExpiresAt = json['expiresAt'] as num;
    final int expectedExpiresAt = midnight
        .add(const Duration(hours: 21))
        .millisecondsSinceEpoch;
    if (_dateString(midnight) != date || rawExpiresAt != expectedExpiresAt) {
      throw const FormatException('Invalid daily deadline');
    }
    final List<MoveCandidate> preset = rawPreset
        .map((value) {
          if (value is! Map || value['x'] is! num || value['y'] is! num) {
            throw const FormatException('Invalid daily move');
          }
          final num rawX = value['x'] as num;
          final num rawY = value['y'] as num;
          final int x = rawX.toInt();
          final int y = rawY.toInt();
          if (rawX != x ||
              rawY != y ||
              !GameEngine.coordinate(x) ||
              !GameEngine.coordinate(y)) {
            throw const FormatException('Invalid daily coordinates');
          }
          return MoveCandidate(x, y);
        })
        .toList(growable: false);
    final GameSnapshot position = GameEngine.replay(preset);
    if (position.status != GameStatus.playing ||
        position.currentPlayer != Player.one) {
      throw const FormatException('Invalid daily position');
    }
    return DailyChallenge(
      id: json['id'] as String,
      date: date,
      preset: preset,
      expiresAt: expectedExpiresAt,
    );
  }

  final String id;
  final String date;
  final List<MoveCandidate> preset;
  final int expiresAt;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'date': date,
    'version': 1,
    'preset': <Map<String, int>>[
      for (final MoveCandidate move in preset)
        <String, int>{'x': move.x, 'y': move.y},
    ],
    'expiresAt': expiresAt,
  };

  bool get isCurrent => isCurrentAt(DateTime.now().millisecondsSinceEpoch);

  bool isCurrentAt(int millisecondsSinceEpoch) {
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpoch,
      isUtc: true,
    );
    return date == _dateString(now.add(const Duration(hours: 3))) &&
        millisecondsSinceEpoch < expiresAt;
  }

  @override
  List<Object> get props => <Object>[id, date, preset, expiresAt];
}

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

final class DailyStanding extends Equatable {
  const new({
    required this.rank,
    required this.username,
    required this.moves,
    required this.completedAt,
  });

  factory fromJson(Map<String, dynamic> json) => DailyStanding(
    rank: (json['rank'] as num).toInt(),
    username: json['username'] as String,
    moves: (json['moves'] as num).toInt(),
    completedAt: (json['completedAt'] as num).toInt(),
  );

  final int rank;
  final String username;
  final int moves;
  final int completedAt;

  Map<String, Object> toJson() => <String, Object>{
    'rank': rank,
    'username': username,
    'moves': moves,
    'completedAt': completedAt,
  };

  @override
  List<Object> get props => <Object>[rank, username, moves, completedAt];
}

final class DailySnapshot extends Equatable {
  const new({
    required this.username,
    required this.challenge,
    required this.leaderboard,
    required this.ownBest,
    required this.serverNow,
    required this.serverOffset,
    this.rank,
  });

  factory fromJson(Map<String, dynamic> json) {
    final Object? rawChallenge = json['challenge'];
    final Object? rawLeaderboard = json['leaderboard'];
    if (rawChallenge is! Map<String, dynamic> || rawLeaderboard is! List) {
      throw const FormatException('Invalid daily response');
    }
    return DailySnapshot(
      username: json['username'] as String?,
      challenge: DailyChallenge.fromJson(rawChallenge),
      leaderboard: rawLeaderboard
          .map(
            (value) =>
                DailyStanding.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false),
      ownBest: (json['ownBest'] as num?)?.toInt(),
      serverNow: (json['now'] as num).toInt(),
      serverOffset: json['serverOffset'] is num
          ? (json['serverOffset'] as num).toInt()
          : (json['now'] as num).toInt() -
                DateTime.now().millisecondsSinceEpoch,
      rank: (json['rank'] as num?)?.toInt(),
    );
  }

  final String? username;
  final DailyChallenge challenge;
  final List<DailyStanding> leaderboard;
  final int? ownBest;
  final int serverNow;
  final int serverOffset;
  final int? rank;

  Map<String, Object?> toJson() => <String, Object?>{
    'username': username,
    'challenge': challenge.toJson(),
    'leaderboard': <Map<String, Object>>[
      for (final DailyStanding standing in leaderboard) standing.toJson(),
    ],
    'ownBest': ownBest,
    'now': serverNow,
    'serverOffset': serverOffset,
    'rank': rank,
  };

  @override
  List<Object?> get props => <Object?>[
    username,
    challenge,
    leaderboard,
    ownBest,
    serverNow,
    serverOffset,
    rank,
  ];

  bool get isCurrent => challenge.isCurrentAt(
    DateTime.now().millisecondsSinceEpoch + serverOffset,
  );
}

final class PendingDailyResult extends Equatable {
  const new({
    required this.id,
    required this.owner,
    required this.challengeId,
    required this.expiresAt,
    required this.moves,
  });

  factory fromJson(Map<String, dynamic> json) {
    final Object? rawId = json['id'];
    final Object? rawOwner = json['owner'];
    final Object? rawChallengeId = json['challengeId'];
    final Object? rawExpiresAt = json['expiresAt'];
    final Object? rawMoves = json['moves'];
    if (rawId is! String ||
        rawId.isEmpty ||
        rawOwner is! String ||
        rawOwner.isEmpty ||
        rawChallengeId is! String ||
        rawChallengeId.isEmpty ||
        rawExpiresAt is! num ||
        rawMoves is! List ||
        rawMoves.isEmpty ||
        rawMoves.length > 63) {
      throw const FormatException('Invalid pending daily result');
    }
    final List<MoveCandidate> moves = rawMoves
        .map((value) {
          if (value is! Map || value['x'] is! num || value['y'] is! num) {
            throw const FormatException('Invalid pending daily move');
          }
          final num rawX = value['x'] as num;
          final num rawY = value['y'] as num;
          final int x = rawX.toInt();
          final int y = rawY.toInt();
          if (rawX != x ||
              rawY != y ||
              !GameEngine.coordinate(x) ||
              !GameEngine.coordinate(y)) {
            throw const FormatException('Invalid pending daily coordinates');
          }
          return MoveCandidate(x, y);
        })
        .toList(growable: false);
    return PendingDailyResult(
      id: rawId,
      owner: rawOwner,
      challengeId: rawChallengeId,
      expiresAt: rawExpiresAt.toInt(),
      moves: moves,
    );
  }

  final String id;
  final String owner;
  final String challengeId;
  final int expiresAt;
  final List<MoveCandidate> moves;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'owner': owner,
    'challengeId': challengeId,
    'expiresAt': expiresAt,
    'moves': <Map<String, int>>[
      for (final MoveCandidate move in moves)
        <String, int>{'x': move.x, 'y': move.y},
    ],
  };

  @override
  List<Object> get props => <Object>[id, owner, challengeId, expiresAt, moves];
}
