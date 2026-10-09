import 'package:four3/src/common/services/analytics/analytics_service.dart';

final class FakeAnalyticsService implements AnalyticsService {
  final List<RecordedAnalyticsEvent> events = <RecordedAnalyticsEvent>[];
  bool throwOnTrack = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> gameStarted({
    required String id,
    required String mode,
    String? difficulty,
    int? level,
  }) async {
    if (throwOnTrack) throw StateError('analytics unavailable');
    events.add(
      RecordedAnalyticsEvent('game_start', <String, Object>{
        'id': id,
        'mode': mode,
        'difficulty': ?difficulty,
        'level': ?level,
      }),
    );
  }

  @override
  Future<void> gameFinished({
    required String id,
    required String game,
    required int elapsed,
  }) async {
    if (throwOnTrack) throw StateError('analytics unavailable');
    events.add(
      RecordedAnalyticsEvent('game_end', <String, Object>{
        'id': id,
        'game': game,
        'elapsed': elapsed,
      }),
    );
  }

  @override
  Future<void> gameAbandoned({required String id, required int elapsed}) async {
    if (throwOnTrack) throw StateError('analytics unavailable');
    events.add(
      RecordedAnalyticsEvent('game_abandon', <String, Object>{
        'id': id,
        'elapsed': elapsed,
      }),
    );
  }

  @override
  Future<void> dispose() async {}
}

final class RecordedAnalyticsEvent {
  const new(this.name, this.parameters);

  final String name;
  final Map<String, Object>? parameters;
}
