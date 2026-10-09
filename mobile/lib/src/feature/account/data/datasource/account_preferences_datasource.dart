import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';

abstract interface class AccountPreferencesDatasource {
  const new();

  String? get guestName;
  String? get cachedUsername;
  Future<void> saveGuestName(String value);
  Future<void> saveCachedUsername(String? value);
}

final class AccountPreferencesDatasource$Preferences
    implements AccountPreferencesDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _guestNameKey => 'four-cubed-guest-name';
  String get _offlineAccountKey => 'four-cubed-offline-account-v1';

  @override
  String? get guestName => preferencesDatasourceTool.getString(_guestNameKey);

  @override
  String? get cachedUsername {
    final String? value = preferencesDatasourceTool.getString(
      _offlineAccountKey,
    );
    return value != null && RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(value)
        ? value
        : null;
  }

  @override
  Future<void> saveGuestName(String value) =>
      preferencesDatasourceTool.setString(_guestNameKey, value);

  @override
  Future<void> saveCachedUsername(String? value) => value == null
      ? preferencesDatasourceTool.removeKey(_offlineAccountKey)
      : preferencesDatasourceTool.setString(_offlineAccountKey, value);
}
