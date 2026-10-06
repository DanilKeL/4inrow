abstract interface class LeaderboardDatasource {
  const new();

  Future<Map<String, dynamic>> load();
}
