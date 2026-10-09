import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/common/services/analytics/analytics_service.dart';
import 'package:four3/src/common/services/analytics/server_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('debug mode uses no-op analytics', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final _RestClientFake client = _RestClientFake();
    final AnalyticsService service = const AnalyticsServiceFactory().create(
      buildMode: AnalyticsBuildMode.debug,
      restClient: client,
      preferences: await _preferences(),
    );

    expect(service, isA<AnalyticsService$NoOp>());
    await service.initialize();
    await service.gameStarted(id: 'game-0001', mode: 'local');
    await service.dispose();
    expect(client.requests, isEmpty);
  });

  test(
    'server analytics sends visit and typed game payloads in order',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final _RestClientFake client = _RestClientFake();
      final AnalyticsService$Server service = AnalyticsService$Server(
        client,
        await _preferences(),
        identifier: _identifiers(),
      );
      addTearDown(service.dispose);

      await service.initialize();
      await service.gameStarted(
        id: 'game-0001',
        mode: 'ai',
        difficulty: 'hard',
      );
      await service.gameFinished(
        id: 'game-0001',
        game: '{"version":1}',
        elapsed: 42,
      );
      await service.gameAbandoned(id: 'game-0002', elapsed: 31);
      await _waitFor(() => client.requests.length >= 4);

      expect(client.requests.map((event) => event['type']), <String>[
        'visit',
        'game_start',
        'game_end',
        'game_abandon',
      ]);
      expect(client.requests.first, containsPair('device', 'mobile'));
      expect(client.requests.first, containsPair('browser', 'App'));
      expect(client.requests[1], containsPair('difficulty', 'hard'));
      expect(client.requests[2], containsPair('elapsed', 42));
      expect(
        client.requests.every(
          (event) =>
              event.containsKey('visitor') &&
              event.containsKey('session') &&
              event.containsKey('occurredAt'),
        ),
        isTrue,
      );
    },
  );

  test('visitor persists and a session rotates after thirty minutes', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final PreferencesDatasourceTool preferences = await _preferences();
    DateTime now = DateTime(2026, 10, 9, 12);
    final AnalyticsService$Server first = AnalyticsService$Server(
      _RestClientFake(),
      preferences,
      now: () => now,
      identifier: _identifiers(),
    );
    await first.initialize();
    final String visitor = first.visitor;
    final String session = first.sessionId;
    await first.handleLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 31));
    await first.handleLifecycleState(AppLifecycleState.resumed);

    expect(first.visitor, visitor);
    expect(first.sessionId, isNot(session));
    await first.dispose();

    final AnalyticsService$Server restored = AnalyticsService$Server(
      _RestClientFake(),
      preferences,
      now: () => now,
      identifier: _identifiers(),
    );
    await restored.initialize();
    expect(restored.visitor, visitor);
    expect(restored.sessionId, first.sessionId);
    await restored.dispose();
  });

  test(
    'backgrounding records active time and resuming records a visit',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      DateTime now = DateTime(2026, 10, 9, 12);
      final _RestClientFake client = _RestClientFake();
      final AnalyticsService$Server service = AnalyticsService$Server(
        client,
        await _preferences(),
        now: () => now,
        identifier: _identifiers(),
      );
      addTearDown(service.dispose);

      await service.initialize();
      now = now.add(const Duration(seconds: 35));
      await service.handleLifecycleState(AppLifecycleState.paused);
      await service.handleLifecycleState(AppLifecycleState.paused);
      await service.handleLifecycleState(AppLifecycleState.resumed);
      await _waitFor(() => client.requests.length >= 3);

      expect(client.requests.map((event) => event['type']), <String>[
        'visit',
        'heartbeat',
        'visit',
      ]);
      expect(client.requests[1], containsPair('activeSeconds', 35));
    },
  );

  test('a queued game survives an application restart', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final PreferencesDatasourceTool preferences = await _preferences();
    final AnalyticsService$Server first = AnalyticsService$Server(
      _RestClientFake(alwaysFail: true),
      preferences,
      identifier: _identifiers(),
    );
    await first.initialize();
    await first.gameStarted(id: 'game-0001', mode: 'local');
    final String visitor = first.visitor;
    await first.dispose();

    final _RestClientFake client = _RestClientFake();
    final AnalyticsService$Server restored = AnalyticsService$Server(
      client,
      preferences,
      identifier: _identifiers(),
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    await _waitFor(
      () => client.requests.any((event) => event['type'] == 'game_start'),
    );

    expect(restored.visitor, visitor);
    expect(
      client.requests.map((event) => event['type']),
      containsAllInOrder(<String>['visit', 'game_start', 'visit']),
    );
  });

  test(
    'network failures retain FIFO outbox and retry on the next event',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final _RestClientFake client = _RestClientFake()
        ..responses.add(
          const RestClientException('', failure: RestClientFailure.network),
        );
      final AnalyticsService$Server service = AnalyticsService$Server(
        client,
        await _preferences(),
        identifier: _identifiers(),
      );
      addTearDown(service.dispose);

      await service.initialize();
      await _waitFor(() => client.requests.isNotEmpty);
      expect(service.pendingEvents, 1);

      await service.gameStarted(id: 'game-0001', mode: 'local');
      await _waitFor(() => service.pendingEvents == 0);
      expect(client.requests.map((event) => event['type']), <String>[
        'visit',
        'visit',
        'game_start',
      ]);
    },
  );

  test(
    'invalid client events are dropped without blocking later events',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final _RestClientFake client = _RestClientFake()
        ..responses.add(const RestClientException('', statusCode: 400));
      final AnalyticsService$Server service = AnalyticsService$Server(
        client,
        await _preferences(),
        identifier: _identifiers(),
      );
      addTearDown(service.dispose);

      await service.initialize();
      await service.gameStarted(id: 'game-0001', mode: 'local');
      await _waitFor(() => service.pendingEvents == 0);
      expect(client.requests.map((event) => event['type']), <String>[
        'visit',
        'game_start',
      ]);
    },
  );

  test('outbox stays bounded while the server is unavailable', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final _RestClientFake client = _RestClientFake(alwaysFail: true);
    final AnalyticsService$Server service = AnalyticsService$Server(
      client,
      await _preferences(),
      identifier: _identifiers(),
    );
    addTearDown(service.dispose);

    await service.initialize();
    for (int index = 0; index < 170; index++) {
      await service.gameStarted(id: 'game-$index-00000000', mode: 'local');
    }
    expect(service.pendingEvents, lessThanOrEqualTo(150));
  });
}

Future<PreferencesDatasourceTool> _preferences() async =>
    PreferencesDatasourceTool$Shared(
      sharedPreferences: await SharedPreferences.getInstance(),
    );

String Function() _identifiers() {
  int value = 0;
  return () => 'identifier-${value++}'.padRight(16, '0');
}

Future<void> _waitFor(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out waiting for analytics');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final class _RestClientFake implements RestClient {
  new({this.alwaysFail = false});

  final bool alwaysFail;
  final List<Exception> responses = <Exception>[];
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?>? data,
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  }) async {
    expect(path, '/telemetry');
    requests.add(Map<String, Object?>.from(data ?? const {}));
    if (responses.isNotEmpty) throw responses.removeAt(0);
    if (alwaysFail) {
      throw const RestClientException('', failure: RestClientFailure.network);
    }
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  }) => throw UnimplementedError();

  @override
  void dispose() {}
}
