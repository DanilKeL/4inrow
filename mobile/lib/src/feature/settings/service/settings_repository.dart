import 'package:four3/src/feature/settings/model/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SettingsRepository {
  const new(this._preferences);
  final SharedPreferences _preferences;

  AppSettings load() => AppSettings(
    sound: _preferences.getBool('settings.sound') ?? true,
    volume: _preferences.getDouble('settings.volume') ?? 1,
    animations: _preferences.getBool('settings.animations') ?? true,
    hints: _preferences.getBool('settings.hints') ?? true,
    xrayDefault: _preferences.getBool('settings.xrayDefault') ?? false,
    tutorialSeen: _preferences.getBool('settings.tutorialSeen') ?? false,
  );

  Future<void> save(AppSettings value) async {
    await Future.wait([
      _preferences.setBool('settings.sound', value.sound),
      _preferences.setDouble('settings.volume', value.volume),
      _preferences.setBool('settings.animations', value.animations),
      _preferences.setBool('settings.hints', value.hints),
      _preferences.setBool('settings.xrayDefault', value.xrayDefault),
      _preferences.setBool('settings.tutorialSeen', value.tutorialSeen),
    ]);
  }
}
