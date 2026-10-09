import 'package:equatable/equatable.dart';

import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';

final class MatchStatistics extends Equatable {
  const new({this.total = 0, this.wins = 0, this.losses = 0, this.draws = 0});
  final int total;
  final int wins;
  final int losses;
  final int draws;
  factory fromJson(Map<String, dynamic> json) => MatchStatistics(
    total: (json['total'] as num?)?.toInt() ?? 0,
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    losses: (json['losses'] as num?)?.toInt() ?? 0,
    draws: (json['draws'] as num?)?.toInt() ?? 0,
  );
  @override
  List<Object> get props => [total, wins, losses, draws];
}

final class MatchRating extends Equatable {
  const new({this.points = 1000, this.games = 0});
  final int points;
  final int games;
  factory fromJson(Map<String, dynamic> json) => MatchRating(
    points: (json['points'] as num?)?.toInt() ?? 1000,
    games: (json['games'] as num?)?.toInt() ?? 0,
  );
  @override
  List<Object> get props => [points, games];
}

final class SavedMatch extends Equatable {
  const new({
    required this.id,
    required this.title,
    required this.date,
    required this.names,
    required this.mode,
    required this.elapsed,
    required this.game,
    this.endReason,
    this.ratingChange,
    this.ratingAfter,
  });
  final String id;
  final String title;
  final int date;
  final List<String> names;
  final String mode;
  final int elapsed;
  final GameSnapshot game;
  final String? endReason;
  final int? ratingChange;
  final int? ratingAfter;

  factory fromJson(Map<String, dynamic> json) => SavedMatch(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    date: (json['date'] as num?)?.toInt() ?? 0,
    names: (json['names'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false),
    mode: json['mode']?.toString() ?? 'local',
    elapsed: (json['elapsed'] as num?)?.toInt() ?? 0,
    game: GameEngine.deserialize(json['game']?.toString() ?? ''),
    endReason: json['endReason']?.toString(),
    ratingChange: (json['ratingChange'] as num?)?.toInt(),
    ratingAfter: (json['ratingAfter'] as num?)?.toInt(),
  );
  @override
  List<Object?> get props => [
    id,
    title,
    date,
    names,
    mode,
    elapsed,
    game,
    endReason,
    ratingChange,
    ratingAfter,
  ];
}

final class MatchHistorySnapshot extends Equatable {
  const new({
    required this.username,
    required this.matches,
    required this.statistics,
    required this.rating,
  });
  final String username;
  final List<SavedMatch> matches;
  final MatchStatistics statistics;
  final MatchRating rating;
  factory fromJson(Map<String, dynamic> json) => MatchHistorySnapshot(
    username: json['username']?.toString() ?? '',
    matches: (json['matches'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SavedMatch.fromJson)
        .toList(growable: false),
    statistics: MatchStatistics.fromJson(
      json['statistics'] as Map<String, dynamic>? ?? const {},
    ),
    rating: MatchRating.fromJson(
      json['rating'] as Map<String, dynamic>? ?? const {},
    ),
  );
  @override
  List<Object> get props => [username, matches, statistics, rating];
}

final class PendingMatch extends Equatable {
  const new({
    required this.owner,
    required this.id,
    required this.names,
    required this.mode,
    required this.elapsed,
    required this.game,
  });

  factory fromJson(Map<String, dynamic> json) {
    final String owner = json['owner']?.toString() ?? '';
    final String id = json['id']?.toString() ?? '';
    final String mode = json['mode']?.toString() ?? '';
    final List<String> names = (json['names'] as List? ?? const <Object>[])
        .map((value) => value.toString())
        .toList(growable: false);
    final GameSnapshot game = GameEngine.deserialize(
      json['game']?.toString() ?? '',
    );
    final int elapsed = (json['elapsed'] as num?)?.toInt() ?? -1;
    if (!RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(owner) ||
        id.isEmpty ||
        id.length > 160 ||
        !<String>{'local', 'ai'}.contains(mode) ||
        names.length != 2 ||
        names.any((name) => name.length > 100) ||
        elapsed < 0 ||
        elapsed > 365 * 86400 ||
        game.status == GameStatus.playing) {
      throw const FormatException('Invalid pending match');
    }
    return PendingMatch(
      owner: owner,
      id: id,
      names: names,
      mode: mode,
      elapsed: elapsed,
      game: game,
    );
  }

  final String owner;
  final String id;
  final List<String> names;
  final String mode;
  final int elapsed;
  final GameSnapshot game;

  Map<String, Object> toJson() => <String, Object>{
    'owner': owner,
    'id': id,
    'names': names,
    'mode': mode,
    'elapsed': elapsed,
    'game': GameEngine.serialize(game),
  };

  Map<String, Object> toRequest() => <String, Object>{
    'owner': owner,
    'id': id,
    'names': names,
    'mode': mode,
    'elapsed': elapsed,
    'game': GameEngine.serialize(game),
  };

  @override
  List<Object> get props => <Object>[owner, id, names, mode, elapsed, game];
}
