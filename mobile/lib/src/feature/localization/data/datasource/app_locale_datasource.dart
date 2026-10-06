import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';

abstract interface class AppLocaleDatasource {
  const new();

  String? loadLanguageTag();
  Future<void> saveLanguageTag(String? languageTag);
}

final class AppLocaleDatasource$Preferences implements AppLocaleDatasource {
  const new({required this.preferencesDatasourceTool});

  static const String preferenceKey = 'settings.locale';

  final PreferencesDatasourceTool preferencesDatasourceTool;

  @override
  String? loadLanguageTag() =>
      preferencesDatasourceTool.getString(preferenceKey);

  @override
  Future<void> saveLanguageTag(String? languageTag) => languageTag == null
      ? preferencesDatasourceTool.removeKey(preferenceKey)
      : preferencesDatasourceTool.setString(preferenceKey, languageTag);
}
