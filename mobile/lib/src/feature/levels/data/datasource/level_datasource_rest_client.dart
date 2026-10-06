import 'package:four3/src/common/rest_client/rest_client.dart';

abstract interface class LevelRemoteDatasource {
  const new();

  Future<Map<String, dynamic>> sync({
    required String owner,
    required Map<int, int> best,
  });
}

final class LevelRemoteDatasource$RestClient implements LevelRemoteDatasource {
  const new({required this.restClient});

  final RestClient restClient;

  @override
  Future<Map<String, dynamic>> sync({
    required String owner,
    required Map<int, int> best,
  }) => restClient.post(
    '/auth/levels',
    data: <String, Object?>{
      'owner': owner,
      'best': <String, int>{
        for (final MapEntry<int, int> entry in best.entries)
          '${entry.key}': entry.value,
      },
    },
  );
}
