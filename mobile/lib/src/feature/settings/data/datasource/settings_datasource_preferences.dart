import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/settings/data/datasource/settings_datasource.dart';
import 'package:four3/src/feature/settings/data/model/app_settings_dto.dart';

final class SettingsDatasource$Preferences implements SettingsDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;

  String get _soundKey => 'settings.sound';
  String get _volumeKey => 'settings.volume';
  String get _animationsKey => 'settings.animations';
  String get _hintsKey => 'settings.hints';
  String get _xrayDefaultKey => 'settings.xrayDefault';
  String get _tutorialSeenKey => 'settings.tutorialSeen';

  @override
  AppSettingsDto load() => AppSettingsDto(
    sound: preferencesDatasourceTool.getBool(_soundKey) ?? true,
    volume: preferencesDatasourceTool.getDouble(_volumeKey) ?? 1,
    animations: preferencesDatasourceTool.getBool(_animationsKey) ?? true,
    hints: preferencesDatasourceTool.getBool(_hintsKey) ?? true,
    xrayDefault: preferencesDatasourceTool.getBool(_xrayDefaultKey) ?? false,
    tutorialSeen: preferencesDatasourceTool.getBool(_tutorialSeenKey) ?? false,
  );

  @override
  Future<void> save(AppSettingsDto value) async {
    await Future.wait([
      preferencesDatasourceTool.setBool(_soundKey, value: value.sound),
      preferencesDatasourceTool.setDouble(_volumeKey, value.volume),
      preferencesDatasourceTool.setBool(
        _animationsKey,
        value: value.animations,
      ),
      preferencesDatasourceTool.setBool(_hintsKey, value: value.hints),
      preferencesDatasourceTool.setBool(
        _xrayDefaultKey,
        value: value.xrayDefault,
      ),
      preferencesDatasourceTool.setBool(
        _tutorialSeenKey,
        value: value.tutorialSeen,
      ),
    ]);
  }
}
