import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';

abstract interface class AccountPreferencesDatasource {
  const new();

  String? get guestName;
  Future<void> saveGuestName(String value);
}

final class AccountPreferencesDatasource$Preferences
    implements AccountPreferencesDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _guestNameKey => 'four-cubed-guest-name';

  @override
  String? get guestName => preferencesDatasourceTool.getString(_guestNameKey);

  @override
  Future<void> saveGuestName(String value) =>
      preferencesDatasourceTool.setString(_guestNameKey, value);
}
