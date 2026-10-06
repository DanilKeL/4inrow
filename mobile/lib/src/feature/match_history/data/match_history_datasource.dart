import 'package:four3/src/common/rest_client/rest_client.dart';

abstract interface class MatchHistoryDatasource {
  Future<Map<String, dynamic>> load();

  Future<Map<String, dynamic>> save(Map<String, Object?> data);

  Future<Map<String, dynamic>> rename(Map<String, Object?> data);

  Future<Map<String, dynamic>> remove(Map<String, Object?> data);
}

final class MatchHistoryDatasource$RestClient
    implements MatchHistoryDatasource {
  const new({required this._restClient});

  final RestClient _restClient;

  @override
  Future<Map<String, dynamic>> load() => _restClient.get('/auth/history');

  @override
  Future<Map<String, dynamic>> save(Map<String, Object?> data) =>
      _restClient.post('/auth/history', data: data);

  @override
  Future<Map<String, dynamic>> rename(Map<String, Object?> data) =>
      _restClient.post('/auth/history/rename', data: data);

  @override
  Future<Map<String, dynamic>> remove(Map<String, Object?> data) =>
      _restClient.post('/auth/history/remove', data: data);
}
