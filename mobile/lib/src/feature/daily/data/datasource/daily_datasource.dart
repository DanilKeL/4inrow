import 'package:four3/src/common/rest_client/rest_client.dart';

abstract interface class DailyRemoteDatasource {
  const new();

  Future<Map<String, dynamic>> load();
  Future<Map<String, dynamic>> submit({
    required String owner,
    required String challengeId,
    required List<Map<String, int>> moves,
  });
}

final class DailyRemoteDatasource$RestClient implements DailyRemoteDatasource {
  const new({required this.restClient});

  final RestClient restClient;

  @override
  Future<Map<String, dynamic>> load() => restClient.get('/daily');

  @override
  Future<Map<String, dynamic>> submit({
    required String owner,
    required String challengeId,
    required List<Map<String, int>> moves,
  }) => restClient.post(
    '/daily/results',
    data: <String, Object>{
      'owner': owner,
      'challengeId': challengeId,
      'moves': moves,
    },
  );
}
