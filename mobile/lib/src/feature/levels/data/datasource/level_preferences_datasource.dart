import 'dart:convert';

import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';

abstract interface class LevelPreferencesDatasource {
  const new();

  LevelProgressCache load();
  Future<void> save(LevelProgressCache cache);
}

final class LevelProgressCache {
  const new({
    this.guestBest = const <int, int>{},
    this.accounts = const <String, Map<int, int>>{},
    this.legacyPending = false,
    this.dirtyAccounts = const <String>{},
  });

  final Map<int, int> guestBest;
  final Map<String, Map<int, int>> accounts;
  final bool legacyPending;
  final Set<String> dirtyAccounts;

  Map<int, int> bestFor(String? owner) => Map<int, int>.of(
    owner == null ? guestBest : accounts[owner] ?? const <int, int>{},
  );

  LevelProgressCache copyWith({
    Map<int, int>? guestBest,
    Map<String, Map<int, int>>? accounts,
    bool? legacyPending,
    Set<String>? dirtyAccounts,
  }) => LevelProgressCache(
    guestBest: guestBest ?? this.guestBest,
    accounts: accounts ?? this.accounts,
    legacyPending: legacyPending ?? this.legacyPending,
    dirtyAccounts: dirtyAccounts ?? this.dirtyAccounts,
  );
}

final class LevelPreferencesDatasource$Preferences
    implements LevelPreferencesDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _bestMovesKey => 'four-cubed-levels-v1';

  @override
  LevelProgressCache load() {
    final String? encoded = preferencesDatasourceTool.getString(_bestMovesKey);
    if (encoded == null) return const LevelProgressCache();
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        return const LevelProgressCache();
      }
      if (decoded['version'] == 2) {
        final Map<int, int> guest = _clean(decoded['guest']);
        final Map<String, Map<int, int>> accounts = <String, Map<int, int>>{};
        final Object? rawAccounts = decoded['accounts'];
        if (rawAccounts is Map<String, dynamic>) {
          for (final MapEntry<String, dynamic> entry in rawAccounts.entries) {
            if (RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(entry.key)) {
              accounts[entry.key] = _clean(entry.value);
            }
          }
        }
        return LevelProgressCache(
          guestBest: guest,
          accounts: accounts,
          legacyPending: decoded['legacyPending'] == true,
          dirtyAccounts: (decoded['dirtyAccounts'] as List? ?? const <Object>[])
              .whereType<String>()
              .where((owner) => RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(owner))
              .toSet(),
        );
      }
      final Map<int, int> legacy = _clean(decoded);
      return LevelProgressCache(
        guestBest: legacy,
        legacyPending: legacy.isNotEmpty,
      );
    } on FormatException {
      return const LevelProgressCache();
    }
  }

  @override
  Future<void> save(LevelProgressCache cache) =>
      preferencesDatasourceTool.setString(
        _bestMovesKey,
        jsonEncode(<String, Object>{
          'version': 2,
          'guest': _encode(cache.guestBest),
          'accounts': <String, Map<String, int>>{
            for (final MapEntry<String, Map<int, int>> entry
                in cache.accounts.entries)
              entry.key: _encode(entry.value),
          },
          'legacyPending': cache.legacyPending,
          'dirtyAccounts': cache.dirtyAccounts.toList(growable: false),
        }),
      );

  static Map<int, int> _clean(Object? value) {
    if (value is! Map) return <int, int>{};
    final Map<int, int> result = <int, int>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final int? id = int.tryParse(entry.key.toString());
      final Object? moves = entry.value;
      if (id != null &&
          id >= 1 &&
          id <= 40 &&
          moves is int &&
          moves > 0 &&
          moves <= 63) {
        result[id] = moves;
      }
    }
    return result;
  }

  static Map<String, int> _encode(Map<int, int> values) => <String, int>{
    for (final MapEntry<int, int> entry in values.entries)
      '${entry.key}': entry.value,
  };
}
