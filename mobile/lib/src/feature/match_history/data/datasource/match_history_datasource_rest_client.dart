import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/match_history/data/datasource/match_history_datasource.dart';

final class MatchHistoryDatasource$RestClient
    implements MatchHistoryDatasource {
  const new({required this.restClient});

  final RestClient restClient;

  @override
  Future<Map<String, dynamic>> load() => restClient.get('/auth/history');

  @override
  Future<Map<String, dynamic>> save(Map<String, Object?> data) =>
      restClient.post('/auth/history', data: data);

  @override
  Future<Map<String, dynamic>> rename(Map<String, Object?> data) =>
      restClient.post('/auth/history/rename', data: data);

  @override
  Future<Map<String, dynamic>> remove(Map<String, Object?> data) =>
      restClient.post('/auth/history/remove', data: data);
}
