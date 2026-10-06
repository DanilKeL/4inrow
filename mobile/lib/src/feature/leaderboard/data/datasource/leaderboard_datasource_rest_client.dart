import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/leaderboard/data/datasource/leaderboard_datasource.dart';

final class LeaderboardDatasource$RestClient implements LeaderboardDatasource {
  const new({required this.restClient});

  final RestClient restClient;

  @override
  Future<Map<String, dynamic>> load() => restClient.get('/auth/leaderboard');
}
