import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/common/services/analytics/analytics_service.dart';

enum AnalyticsBuildMode {
  debug,
  profile,
  release;

  static AnalyticsBuildMode get current {
    if (kReleaseMode) return release;
    if (kProfileMode) return profile;
    return debug;
  }
}

final class AnalyticsServiceFactory {
  const new();

  AnalyticsService create({
    required AnalyticsBuildMode buildMode,
    required RestClient restClient,
    required PreferencesDatasourceTool preferences,
  }) => switch (buildMode) {
    AnalyticsBuildMode.debug => const AnalyticsService$NoOp(),
    AnalyticsBuildMode.profile || AnalyticsBuildMode.release =>
      AnalyticsService$Server(restClient, preferences),
  };
}

final class AnalyticsService$Server
    with WidgetsBindingObserver
    implements AnalyticsService {
  new(
    this._restClient,
    this._preferences, {
    DateTime Function()? now,
    String Function()? identifier,
    this._heartbeatInterval = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now,
       _identifier = identifier ?? _randomIdentifier,
       super();

  static const String _visitorKey = 'four_analytics_visitor_v1';
  static const String _sessionKey = 'four_analytics_session_v1';
  static const String _outboxKey = 'four_analytics_outbox_v1';
  static const Duration _sessionTimeout = Duration(minutes: 30);
  static const int _outboxLimit = 150;

  final RestClient _restClient;
  final PreferencesDatasourceTool _preferences;
  final DateTime Function() _now;
  final String Function() _identifier;
  final Duration _heartbeatInterval;
  final List<Map<String, Object?>> _queue = <Map<String, Object?>>[];

  late String _visitor;
  late _AnalyticsSession _session;
  Timer? _heartbeatTimer;
  DateTime? _heartbeatAt;
  Future<void> _writes = Future<void>.value();
  Future<void>? _flushTask;
  bool _initialized = false;
  bool _active = false;
  bool _disposed = false;
  bool _sending = false;
  bool _flushRequested = false;

  @visibleForTesting
  int get pendingEvents => _queue.length;

  @visibleForTesting
  String get visitor => _visitor;

  @visibleForTesting
  String get sessionId => _session.id;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _restoreOutbox();
    _visitor = _restoreVisitor();
    _session = _restoreSession();
    _initialized = true;
    _active = _isActive(WidgetsBinding.instance.lifecycleState);
    _heartbeatAt = _now();
    WidgetsBinding.instance.addObserver(this);
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_heartbeat()),
    );
    await _visit();
  }

  @override
  Future<void> gameStarted({
    required String id,
    required String mode,
    String? difficulty,
    int? level,
  }) => _enqueue(<String, Object?>{
    'type': 'game_start',
    'id': id,
    'mode': mode,
    'difficulty': ?difficulty,
    'level': ?level,
  });

  @override
  Future<void> gameFinished({
    required String id,
    required String game,
    required int elapsed,
  }) => _enqueue(<String, Object?>{
    'type': 'game_end',
    'id': id,
    'game': game,
    'elapsed': elapsed,
  });

  @override
  Future<void> gameAbandoned({required String id, required int elapsed}) =>
      _enqueue(<String, Object?>{
        'type': 'game_abandon',
        'id': id,
        'elapsed': elapsed,
      });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !_initialized) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resume());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_background());
    }
  }

  @visibleForTesting
  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _resume();
    } else {
      await _background();
    }
  }

  Future<void> _resume() async {
    if (_active) return;
    final DateTime now = _now();
    if (now.difference(_session.lastSeen) >= _sessionTimeout) {
      _session = _AnalyticsSession(
        id: _identifier(),
        lastSeen: now,
        activeSeconds: 0,
      );
    }
    _active = true;
    _heartbeatAt = now;
    await _visit();
  }

  Future<void> _background() async {
    if (!_active) return;
    await _heartbeat();
    _active = false;
    _heartbeatAt = null;
  }

  Future<void> _visit() async {
    final DateTime now = _now();
    _session = _session.copyWith(lastSeen: now);
    await _persistSession();
    await _enqueue(<String, Object?>{
      'type': 'visit',
      'device': 'mobile',
      'browser': 'App',
      'referrer': '',
    });
  }

  Future<void> _heartbeat() async {
    if (!_active || _disposed) return;
    final DateTime now = _now();
    final DateTime previous = _heartbeatAt ?? now;
    final int elapsed = now.difference(previous).inSeconds.clamp(0, 60);
    _heartbeatAt = now;
    _session = _session.copyWith(
      lastSeen: now,
      activeSeconds: _session.activeSeconds + elapsed,
    );
    await _persistSession();
    await _enqueue(<String, Object?>{
      'type': 'heartbeat',
      'activeSeconds': _session.activeSeconds,
    });
  }

  Future<void> _enqueue(Map<String, Object?> event) async {
    if (!_initialized || _disposed) return;
    final Map<String, Object?> queued = <String, Object?>{
      ...event,
      'visitor': _visitor,
      'session': _session.id,
      'occurredAt': _now().millisecondsSinceEpoch,
    };
    if (queued['type'] == 'heartbeat') {
      final int protected = _sending ? 1 : 0;
      for (int index = protected; index < _queue.length; index++) {
        if (_queue[index]['type'] == 'heartbeat' &&
            _queue[index]['session'] == _session.id) {
          _queue.removeAt(index);
          break;
        }
      }
    }
    _queue.add(queued);
    _trimOutbox();
    await _persistOutbox();
    _startFlush();
  }

  void _trimOutbox() {
    while (_queue.length > _outboxLimit) {
      final int protected = _sending ? 1 : 0;
      int heartbeat = -1;
      for (int index = protected; index < _queue.length; index++) {
        if (_queue[index]['type'] == 'heartbeat') {
          heartbeat = index;
          break;
        }
      }
      _queue.removeAt(heartbeat >= 0 ? heartbeat : protected);
    }
  }

  void _startFlush() {
    if (_disposed) return;
    if (_flushTask != null) {
      _flushRequested = true;
      return;
    }
    final Future<void> task = _flush();
    _flushTask = task;
    unawaited(
      task.whenComplete(() {
        _flushTask = null;
        final bool requested = _flushRequested;
        _flushRequested = false;
        if (requested && _queue.isNotEmpty && !_disposed) {
          _startFlush();
        }
      }),
    );
  }

  Future<void> _flush() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final Map<String, Object?> event = _queue.first;
        bool remove = false;
        try {
          await _restClient.post('/telemetry', data: event);
          remove = true;
        } on RestClientException catch (error) {
          final int? status = error.statusCode;
          if (error.failure == RestClientFailure.network ||
              status == 429 ||
              (status != null && status >= 500)) {
            break;
          }
          remove = true;
        } on Object {
          break;
        }
        if (remove && _queue.isNotEmpty && identical(_queue.first, event)) {
          _queue.removeAt(0);
          await _persistOutbox();
        }
      }
    } finally {
      _sending = false;
    }
  }

  String _restoreVisitor() {
    final String? saved = _preferences.getString(_visitorKey);
    if (saved != null && _validToken(saved)) return saved;
    final String created = _identifier();
    unawaited(_chainWrite(() => _preferences.setString(_visitorKey, created)));
    return created;
  }

  _AnalyticsSession _restoreSession() {
    final DateTime now = _now();
    try {
      final Object? decoded = jsonDecode(
        _preferences.getString(_sessionKey) ?? 'null',
      );
      if (decoded is Map<String, dynamic>) {
        final _AnalyticsSession session = _AnalyticsSession.fromJson(decoded);
        if (_validToken(session.id) &&
            !now.isBefore(session.lastSeen) &&
            now.difference(session.lastSeen) < _sessionTimeout) {
          return session;
        }
      }
    } on Object {
      // Start a clean session if local telemetry state is malformed.
    }
    return _AnalyticsSession(
      id: _identifier(),
      lastSeen: now,
      activeSeconds: 0,
    );
  }

  void _restoreOutbox() {
    try {
      final Object? decoded = jsonDecode(
        _preferences.getString(_outboxKey) ?? '[]',
      );
      if (decoded is! List) return;
      for (final Object? item in decoded.take(_outboxLimit)) {
        if (item is Map) {
          _queue.add(<String, Object?>{
            for (final MapEntry<Object?, Object?> entry in item.entries)
              if (entry.key is String) entry.key! as String: entry.value,
          });
        }
      }
    } on Object {
      // A corrupt queue must not prevent the application from starting.
    }
  }

  Future<void> _persistSession() => _chainWrite(
    () => _preferences.setString(_sessionKey, jsonEncode(_session.toJson())),
  );

  Future<void> _persistOutbox() {
    final String encoded = jsonEncode(_queue);
    return _chainWrite(() => _preferences.setString(_outboxKey, encoded));
  }

  Future<void> _chainWrite(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).catchError((Object _) {});
    return _writes;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    if (_active) await _heartbeat();
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _persistOutbox();
    await _writes;
    await _flushTask;
  }

  static bool _isActive(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  static bool _validToken(String value) =>
      RegExp(r'^[a-zA-Z0-9-]{8,140}$').hasMatch(value);

  static String _randomIdentifier() {
    final Random random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

final class _AnalyticsSession {
  const new({
    required this.id,
    required this.lastSeen,
    required this.activeSeconds,
  });

  factory fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    final Object? lastSeen = json['lastSeen'];
    final Object? activeSeconds = json['activeSeconds'];
    if (id is! String ||
        lastSeen is! int ||
        activeSeconds is! int ||
        activeSeconds < 0) {
      throw const FormatException('Invalid analytics session');
    }
    return _AnalyticsSession(
      id: id,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeen),
      activeSeconds: activeSeconds,
    );
  }

  final String id;
  final DateTime lastSeen;
  final int activeSeconds;

  _AnalyticsSession copyWith({DateTime? lastSeen, int? activeSeconds}) =>
      _AnalyticsSession(
        id: id,
        lastSeen: lastSeen ?? this.lastSeen,
        activeSeconds: activeSeconds ?? this.activeSeconds,
      );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
    'activeSeconds': activeSeconds,
  };
}
