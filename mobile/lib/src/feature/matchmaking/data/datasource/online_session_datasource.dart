import 'dart:convert';

import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';

abstract interface class OnlineSessionDatasource {
  const new();

  Map<String, dynamic>? loadSession();
  Map<String, dynamic>? loadSearch();
  Future<void> saveSession(Map<String, dynamic> value);
  Future<void> saveSearch(Map<String, dynamic> value);
  Future<void> clearSession();
  Future<void> clearSearch();
}

final class OnlineSessionDatasource$Preferences
    implements OnlineSessionDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _sessionKey => 'four-cubed-online-session';
  String get _searchKey => 'four-cubed-online-search';

  @override
  Map<String, dynamic>? loadSession() => _read(_sessionKey);

  @override
  Map<String, dynamic>? loadSearch() => _read(_searchKey);

  @override
  Future<void> saveSession(Map<String, dynamic> value) =>
      _save(_sessionKey, value);

  @override
  Future<void> saveSearch(Map<String, dynamic> value) =>
      _save(_searchKey, value);

  @override
  Future<void> clearSession() =>
      preferencesDatasourceTool.removeKey(_sessionKey);

  @override
  Future<void> clearSearch() => preferencesDatasourceTool.removeKey(_searchKey);

  Map<String, dynamic>? _read(String key) {
    try {
      final Object? decoded = jsonDecode(
        preferencesDatasourceTool.getString(key) ?? 'null',
      );
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _save(String key, Map<String, dynamic> value) =>
      preferencesDatasourceTool.setString(key, jsonEncode(value));
}
