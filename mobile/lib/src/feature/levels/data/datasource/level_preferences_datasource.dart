import 'dart:convert';

import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';

abstract interface class LevelPreferencesDatasource {
  const new();

  Map<int, int> loadBest();
  Future<void> saveBest(Map<int, int> values);
}

final class LevelPreferencesDatasource$Preferences
    implements LevelPreferencesDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _bestMovesKey => 'four-cubed-levels-v1';

  @override
  Map<int, int> loadBest() {
    final String? encoded = preferencesDatasourceTool.getString(_bestMovesKey);
    if (encoded == null) return <int, int>{};
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return <int, int>{};
      final Map<int, int> result = <int, int>{};
      for (final MapEntry<String, dynamic> entry in decoded.entries) {
        final int? id = int.tryParse(entry.key);
        final Object? value = entry.value;
        if (id != null && value is int && value > 0 && value <= 63) {
          result[id] = value;
        }
      }
      return result;
    } on FormatException {
      return <int, int>{};
    }
  }

  @override
  Future<void> saveBest(Map<int, int> values) =>
      preferencesDatasourceTool.setString(
        _bestMovesKey,
        jsonEncode(<String, int>{
          for (final MapEntry<int, int> entry in values.entries)
            '${entry.key}': entry.value,
        }),
      );
}
