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
