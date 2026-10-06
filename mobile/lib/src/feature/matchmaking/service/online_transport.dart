import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

sealed class OnlineTransportEvent {
  const new();
}

enum OnlineTransportFailure { invalidResponse, connectionLost }

typedef OnlineSocketFactory = WebSocketChannel Function(
  Uri endpoint,
  Map<String, String>? headers,
);

final class OnlineTransportEvent$Status extends OnlineTransportEvent {
  const new(this.status);
  final String status;
}

final class OnlineTransportEvent$Message extends OnlineTransportEvent {
  const new(this.json);
  final Map<String, dynamic> json;
}

final class OnlineTransportEvent$Failure extends OnlineTransportEvent {
  const new(this.message, {this.failure});
  final String message;
  final OnlineTransportFailure? failure;
}

final class OnlineTransport {
  new({
    required this._endpoint,
    required this._preferences,
    required SessionCookieStorage cookieStorage,
    OnlineSocketFactory? socketFactory,
    Future<String?> Function()? cookieReader,
  }) : _socketFactory = socketFactory ?? _defaultSocketFactory,
       _cookieReader = cookieReader ?? cookieStorage.read;

  static const _sessionKey = 'four-cubed-online-session';
  static const _searchKey = 'four-cubed-online-search';
  static const _reconnectLimit = Duration(minutes: 5);
  static const _handshakeTimeout = Duration(seconds: 8);

  final Uri _endpoint;
  final SharedPreferences _preferences;
  final OnlineSocketFactory _socketFactory;
  final Future<String?> Function() _cookieReader;
  final _events = StreamController<OnlineTransportEvent>.broadcast();
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _handshakeTimer;
  Timer? _retryTimer;
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _search;
  Map<String, dynamic>? _command;
  int _generation = 0;
  int _retry = 0;
  DateTime? _retryStarted;
  bool _acknowledged = false;
  bool _disposed = false;

  Stream<OnlineTransportEvent> get events => _events.stream;
  bool get hasRestorableState =>
      _readSession() != null || _readSearch() != null;

  Future<void> connect(Map<String, dynamic> command) async {
    await disconnect();
    if (command['type'] == 'quick_find') {
      _search = {
        ...command,
        'searchId': command['searchId'] ?? _randomHex(16),
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      _command = Map<String, dynamic>.from(_search!);
      await _save(_searchKey, _search!);
      await _remove(_sessionKey);
      _session = null;
    } else if (command['type'] == 'resume') {
      _session = {
        'code': command['code'],
        'token': command['token'],
        'player': command['player'],
      };
      _command = command;
    } else {
      _session = null;
      await _remove(_sessionKey);
      _command = command;
    }
    _retry = 0;
    _retryStarted = null;
    _emitStatus('connecting');
    await _open();
  }

  Future<bool> restore() async {
    final Map<String, dynamic>? session = _readSession();
    if (session != null) {
      await connect({
        'type': 'resume',
        'code': session['code'],
        'token': session['token'],
        'player': session['player'],
      });
      return true;
    }
    final Map<String, dynamic>? search = _readSearch();
    if (search != null) {
      await connect(search);
      return true;
    }
    return false;
  }

  bool send(Map<String, dynamic> command) {
    if (!_acknowledged || _socket == null) return false;
    try {
      _socket!.sink.add(jsonEncode(command));
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> wake() async {
    if (_command == null || _disposed) return;
    _emitStatus('reconnecting');
    await _closeSocket();
    _retry = 0;
    _retryStarted = null;
    await _open();
  }

  Future<void> leave() async {
    send(const {'type': 'leave'});
    _session = null;
    _search = null;
    await _remove(_sessionKey);
    await _remove(_searchKey);
    await disconnect();
  }

  Future<void> disconnect({bool clearPersistence = false}) async {
    _generation++;
    _clearTimers();
    _acknowledged = false;
    await _closeSocket();
    if (clearPersistence) {
      _session = null;
      _search = null;
      await _remove(_sessionKey);
      await _remove(_searchKey);
    }
    _command = null;
  }

  Future<void> _open() async {
    final Map<String, dynamic>? command = _command;
    if (command == null || _disposed) return;
    final int generation = ++_generation;
    _acknowledged = false;
    try {
      final String? cookie = await _cookieReader();
      final WebSocketChannel socket = _socketFactory(
        _endpoint,
        cookie == null ? null : {'Cookie': cookie},
      );
      _socket = socket;
      _handshakeTimer = Timer(_handshakeTimeout, () {
        if (generation != _generation || _acknowledged) return;
        unawaited(_connectionLost());
      });
      await socket.ready;
      if (generation != _generation) return;
      socket.sink.add(jsonEncode(command));
      _subscription = socket.stream.listen(
        (raw) => _handle(raw, generation),
        onError: (_) => _connectionLost(generation),
        onDone: () => _connectionLost(generation),
        cancelOnError: true,
      );
    } on Exception {
      if (generation == _generation) await _connectionLost(generation);
    }
  }

  Future<void> _handle(Object? raw, int generation) async {
    if (generation != _generation) return;
    Map<String, dynamic> event;
    try {
      final Object? decoded = jsonDecode(raw.toString());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      event = decoded;
    } on FormatException {
      _events.add(
        const OnlineTransportEvent$Failure(
          '',
          failure: OnlineTransportFailure.invalidResponse,
        ),
      );
      return;
    }
    switch (event['type']) {
      case 'session':
        _acknowledged = true;
        _clearTimers();
        _retry = 0;
        _retryStarted = null;
        _session = {
          'code': event['code'],
          'token': event['token'],
          'player': event['player'],
        };
        _search = null;
        await _save(_sessionKey, _session!);
        await _remove(_searchKey);
        _events.add(OnlineTransportEvent$Message(event));
        _emitStatus('connected');
      case 'queue':
        _acknowledged = true;
        _clearTimers();
        _retry = 0;
        _retryStarted = null;
        _events.add(OnlineTransportEvent$Message(event));
        _emitStatus('connected');
      case 'queue_removed':
        _search = null;
        await _remove(_searchKey);
        _events.add(OnlineTransportEvent$Message(event));
        await disconnect();
      case 'closed':
        _events.add(OnlineTransportEvent$Message(event));
        await disconnect(clearPersistence: true);
        _emitStatus('error');
      case 'error':
        _events.add(OnlineTransportEvent$Message(event));
        if (!_acknowledged) {
          await disconnect(clearPersistence: true);
          _emitStatus('error');
        }
      default:
        _events.add(OnlineTransportEvent$Message(event));
    }
  }

  Future<void> _connectionLost([int? generation]) async {
    if (generation != null && generation != _generation) return;
    _acknowledged = false;
    _clearTimers();
    await _closeSocket();
    if (_command == null || _disposed) return;
    _emitStatus('reconnecting');
    _retryStarted ??= DateTime.now();
    if (DateTime.now().difference(_retryStarted!) >= _reconnectLimit) {
      _events.add(
        const OnlineTransportEvent$Failure(
          '',
          failure: OnlineTransportFailure.connectionLost,
        ),
      );
      _emitStatus('error');
      return;
    }
    final int delayMs = min(500 * (1 << min(_retry++, 5)), 10000);
    _retryTimer = Timer(Duration(milliseconds: delayMs), _open);
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    final WebSocketChannel? socket = _socket;
    _socket = null;
    if (socket != null) await socket.sink.close();
  }

  void _clearTimers() {
    _handshakeTimer?.cancel();
    _retryTimer?.cancel();
    _handshakeTimer = null;
    _retryTimer = null;
  }

  void _emitStatus(String value) {
    if (!_events.isClosed) _events.add(OnlineTransportEvent$Status(value));
  }

  Map<String, dynamic>? _read(String key) {
    try {
      final Object? decoded = jsonDecode(_preferences.getString(key) ?? 'null');
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic>? _readSession() {
    final Map<String, dynamic>? value = _session ?? _read(_sessionKey);
    if (value == null ||
        !RegExp(r'^[A-Z]{5}$').hasMatch(value['code']?.toString() ?? '') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['token']?.toString() ?? '')) {
      return null;
    }
    return value;
  }

  Map<String, dynamic>? _readSearch() {
    final Map<String, dynamic>? value = _search ?? _read(_searchKey);
    final Object? savedAt = value?['savedAt'];
    if (value == null ||
        value['type'] != 'quick_find' ||
        !RegExp(r'^[a-f0-9]{32}$')
            .hasMatch(value['searchId']?.toString() ?? '') ||
        savedAt is! int ||
        DateTime.now().millisecondsSinceEpoch - savedAt >=
            _reconnectLimit.inMilliseconds) {
      return null;
    }
    return value;
  }

  Future<void> _save(String key, Map<String, dynamic> value) =>
      _preferences.setString(key, jsonEncode(value));
  Future<void> _remove(String key) => _preferences.remove(key);

  String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static WebSocketChannel _defaultSocketFactory(
    Uri endpoint,
    Map<String, String>? headers,
  ) => IOWebSocketChannel.connect(
    endpoint,
    headers: headers,
    connectTimeout: _handshakeTimeout,
  );

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _events.close();
  }
}
