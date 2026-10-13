import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/appearance/data/appearance_repository.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PreferencesDatasourceTool> preferences(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    return PreferencesDatasourceTool$Shared(
      sharedPreferences: await SharedPreferences.getInstance(),
    );
  }

  test('cached catalog is available before network refresh', () async {
    final cached = SkinCatalog(
      revision: 3,
      activeSkinId: 'classic',
      skins: builtinSkins,
    );
    final repository = AppearanceRepository(
      baseUri: Uri.parse('https://example.test'),
      preferences: await preferences({
        AppearanceRepository.cacheKey: cached.encode(),
      }),
      client: MockClient((_) async => http.Response('', 503)),
      networkAvailable: () async => true,
    );
    addTearDown(repository.dispose);

    expect(repository.cached().activeSkinId, 'classic');
    expect(await repository.refresh(), isNull);
    expect(repository.cached().revision, 3);
  });

  test('refresh caches a valid catalog and ignores stale revisions', () async {
    final current = SkinCatalog(
      revision: 7,
      activeSkinId: 'nocturne',
      skins: builtinSkins,
    );
    final stale = SkinCatalog(
      revision: 4,
      activeSkinId: 'classic',
      skins: builtinSkins,
    );
    final repository = AppearanceRepository(
      baseUri: Uri.parse('https://example.test'),
      preferences: await preferences({
        AppearanceRepository.cacheKey: current.encode(),
      }),
      client: MockClient((_) async => http.Response(stale.encode(), 200)),
      networkAvailable: () async => true,
    );
    addTearDown(repository.dispose);

    expect(await repository.refresh(), isNull);
    expect(repository.cached().revision, 7);
    expect(repository.cached().activeSkinId, 'nocturne');
  });

  test('SSE catalog is parsed and cached', () async {
    final next = SkinCatalog(
      revision: 2,
      activeSkinId: 'coffee-pieces',
      skins: builtinSkins,
    );
    final repository = AppearanceRepository(
      baseUri: Uri.parse('https://example.test'),
      preferences: await preferences({}),
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode('event: skins\ndata: ${next.encode()}\n\n'),
          ),
          200,
          headers: <String, String>{'content-type': 'text/event-stream'},
        ),
      ),
      networkAvailable: () async => true,
    );
    addTearDown(repository.dispose);

    final completer = Completer<SkinCatalog>();
    final StreamSubscription<SkinCatalog> subscription = repository
        .events()
        .listen(completer.complete);
    final SkinCatalog received = await completer.future.timeout(
      const Duration(seconds: 2),
    );
    await subscription.cancel();

    expect(received.activeSkinId, 'coffee-pieces');
    expect(repository.cached().revision, 2);
  });

  test('offline refresh does not open an HTTP request', () async {
    var requests = 0;
    final repository = AppearanceRepository(
      baseUri: Uri.parse('https://example.test'),
      preferences: await preferences({}),
      client: MockClient((_) async {
        requests++;
        return http.Response('', 200);
      }),
      networkAvailable: () async => false,
    );
    addTearDown(repository.dispose);

    expect(await repository.refresh(), isNull);
    expect(requests, 0);
  });
}
