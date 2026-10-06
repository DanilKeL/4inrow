import 'package:four3/src/feature/leaderboard/domain/model/leaderboard_player.dart';

abstract interface class LeaderboardRepository {
  const new();

  Future<List<LeaderboardPlayer>> load();
}
