import 'package:four3/src/common/rest_client/rest_client.dart';

abstract interface class LeaderboardDatasource {
  Future<Map<String, dynamic>> load();
}

final class LeaderboardDatasource$RestClient implements LeaderboardDatasource {
  const new({required this._restClient});

  final RestClient _restClient;

  @override
  Future<Map<String, dynamic>> load() => _restClient.get('/auth/leaderboard');
}
