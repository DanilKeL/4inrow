abstract interface class AnalyticsService {
  Future<void> initialize();

  Future<void> gameStarted({
    required String id,
    required String mode,
    String? difficulty,
    int? level,
  });

  Future<void> gameFinished({
    required String id,
    required String game,
    required int elapsed,
  });

  Future<void> gameAbandoned({required String id, required int elapsed});

  Future<void> dispose();
}

final class AnalyticsService$NoOp implements AnalyticsService {
  const new();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> gameStarted({
    required String id,
    required String mode,
    String? difficulty,
    int? level,
  }) async {}

  @override
  Future<void> gameFinished({
    required String id,
    required String game,
    required int elapsed,
  }) async {}

  @override
  Future<void> gameAbandoned({
    required String id,
    required int elapsed,
  }) async {}

  @override
  Future<void> dispose() async {}
}
