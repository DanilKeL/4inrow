import 'package:four3/src/feature/leaderboard/data/datasource/leaderboard_datasource.dart';
import 'package:four3/src/feature/leaderboard/domain/model/leaderboard_player.dart';
import 'package:four3/src/feature/leaderboard/domain/repository/leaderboard_repository.dart';

final class LeaderboardRepository$Api implements LeaderboardRepository {
  const new({required this.datasource});

  final LeaderboardDatasource datasource;

  @override
  Future<List<LeaderboardPlayer>> load() async {
    final Map<String, dynamic> json = await datasource.load();
    final List<dynamic> players =
        json['players'] as List<dynamic>? ?? const <dynamic>[];
    return players
        .whereType<Map<String, dynamic>>()
        .map(LeaderboardPlayer.fromJson)
        .toList(growable: false);
  }
}
