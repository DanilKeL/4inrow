import 'package:four3/src/feature/leaderboard/data/leaderboard_datasource.dart';
import 'package:four3/src/feature/leaderboard/model/leaderboard_player.dart';

final class LeaderboardRepository {
  const new({required this._datasource});

  final LeaderboardDatasource _datasource;

  Future<List<LeaderboardPlayer>> load() async {
    final Map<String, dynamic> json = await _datasource.load();
    final List<dynamic> players =
        json['players'] as List<dynamic>? ?? const <dynamic>[];
    return players
        .whereType<Map<String, dynamic>>()
        .map(LeaderboardPlayer.fromJson)
        .toList(growable: false);
  }
}
