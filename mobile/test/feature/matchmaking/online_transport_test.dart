import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/matchmaking/service/online_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('persists search, reconnects and restores a server session', () async {
    SharedPreferences.setMockInitialValues(const {});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String token = List<String>.filled(64, 'a').join();
    final List<_FakeWebSocketChannel> channels = [];
    final List<OnlineTransportEvent> events = [];
    final OnlineTransport transport = OnlineTransport(
      endpoint: Uri.parse('ws://localhost/online'),
      preferences: preferences,
      cookieStorage: const SessionCookieStorage(FlutterSecureStorage()),
      cookieReader: () async => 'four_session=test-cookie',
      socketFactory: (endpoint, headers) {
        expect(endpoint, Uri.parse('ws://localhost/online'));
        expect(headers, {'Cookie': 'four_session=test-cookie'});
        final _FakeWebSocketChannel channel = _FakeWebSocketChannel();
        channels.add(channel);
        return channel;
      },
    );
    final StreamSubscription<OnlineTransportEvent> subscription = transport
        .events
        .listen(events.add);

    await transport.connect(const {'type': 'quick_find', 'name': 'Alice'});
    expect(channels, hasLength(1));
    final Map<String, dynamic> search = _sent(channels.first);
    expect(search['type'], 'quick_find');
    expect(search['searchId'], matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(
      preferences.getString('four-cubed-online-search'),
      contains(search['searchId'].toString()),
    );

    channels.first.serverAdd(jsonEncode(const {'type': 'queue'}));
    await _flush();
    expect(
      events.whereType<OnlineTransportEvent$Status>().map(
        (event) => event.status,
      ),
      contains('connected'),
    );

    await channels.first.serverClose();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(channels, hasLength(2));
    expect(_sent(channels[1])['searchId'], search['searchId']);
    expect(
      events.whereType<OnlineTransportEvent$Status>().map(
        (event) => event.status,
      ),
      contains('reconnecting'),
    );

    channels[1].serverAdd(
      jsonEncode({
        'type': 'session',
        'code': 'ABCDE',
        'token': token,
        'player': 1,
      }),
    );
    await _flush();
    expect(preferences.getString('four-cubed-online-search'), isNull);
    expect(
      preferences.getString('four-cubed-online-session'),
      contains('ABCDE'),
    );

    await subscription.cancel();
    await transport.dispose();

    final List<_FakeWebSocketChannel> restoredChannels = [];
    final OnlineTransport restored = OnlineTransport(
      endpoint: Uri.parse('ws://localhost/online'),
      preferences: preferences,
      cookieStorage: const SessionCookieStorage(FlutterSecureStorage()),
      cookieReader: () async => null,
      socketFactory: (_, _) {
        final _FakeWebSocketChannel channel = _FakeWebSocketChannel();
        restoredChannels.add(channel);
        return channel;
      },
    );
    expect(await restored.restore(), isTrue);
    expect(_sent(restoredChannels.single), {
      'type': 'resume',
      'code': 'ABCDE',
      'token': token,
      'player': 1,
    });
    await restored.dispose();
  });
}

Map<String, dynamic> _sent(_FakeWebSocketChannel channel) {
  final Object? decoded = jsonDecode(channel.outgoing.single! as String);
  if (decoded case final Map<String, dynamic> json) return json;
  throw StateError('Expected a JSON object.');
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

final class _FakeWebSocketChannel
    with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  // Closed explicitly by serverClose or by the transport-owned sink.
  // ignore: close_sinks
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  // Closed by OnlineTransport, which owns the channel returned by the factory.
  // ignore: close_sinks
  late final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  List<Object?> get outgoing => _sink.values;

  void serverAdd(Object value) => _incoming.add(value);

  Future<void> serverClose() => _incoming.close();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _incoming.stream;
}

final class _FakeWebSocketSink implements WebSocketSink {
  final List<Object?> values = [];
  final Completer<void> _done = Completer<void>();

  @override
  void add(Object? data) => values.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final dynamic value in stream) {
      values.add(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
