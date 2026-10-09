import 'dart:convert';

import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';

abstract interface class DailyPreferencesDatasource {
  const new();

  DailySnapshot? loadCached();
  Future<void> saveCached(DailySnapshot snapshot);
  List<PendingDailyResult> loadPending();
  Future<void> savePending(List<PendingDailyResult> pending);
}

final class DailyPreferencesDatasource$Preferences
    implements DailyPreferencesDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  static const String _cacheKey = 'four-cubed-daily-cache-v1';
  static const String _pendingKey = 'four-cubed-daily-pending-v1';

  @override
  DailySnapshot? loadCached() {
    final String? value = preferencesDatasourceTool.getString(_cacheKey);
    if (value == null) return null;
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      return DailySnapshot.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveCached(DailySnapshot snapshot) => preferencesDatasourceTool
      .setString(_cacheKey, jsonEncode(snapshot.toJson()));

  @override
  List<PendingDailyResult> loadPending() {
    final String? value = preferencesDatasourceTool.getString(_pendingKey);
    if (value == null) return <PendingDailyResult>[];
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is! List) return <PendingDailyResult>[];
      final Iterable<Object?> recent = decoded.skip(
        decoded.length > 20 ? decoded.length - 20 : 0,
      );
      return recent
          .whereType<Map<Object?, Object?>>()
          .map(
            (value) =>
                PendingDailyResult.fromJson(Map<String, dynamic>.from(value)),
          )
          .where(
            (value) =>
                value.owner.isNotEmpty &&
                value.moves.isNotEmpty &&
                value.moves.length <= 63,
          )
          .toList(growable: false);
    } on Object {
      return <PendingDailyResult>[];
    }
  }

  @override
  Future<void> savePending(List<PendingDailyResult> pending) =>
      preferencesDatasourceTool.setString(
        _pendingKey,
        jsonEncode(<Map<String, Object>>[
          for (final PendingDailyResult result in pending) result.toJson(),
        ]),
      );
}
