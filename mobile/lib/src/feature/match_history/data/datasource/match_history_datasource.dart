abstract interface class MatchHistoryDatasource {
  const new();

  Future<Map<String, dynamic>> load();
  Future<Map<String, dynamic>> save(Map<String, Object?> data);
  Future<Map<String, dynamic>> rename(Map<String, Object?> data);
  Future<Map<String, dynamic>> remove(Map<String, Object?> data);
}
