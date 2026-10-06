import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/account/data/datasource/account_preferences_datasource.dart';
import 'package:four3/src/feature/matchmaking/data/datasource/online_session_datasource.dart';
import 'package:four3/src/feature/settings/data/datasource/settings_datasource.dart';
import 'package:four3/src/feature/settings/data/datasource/settings_datasource_preferences.dart';
import 'package:four3/src/feature/settings/data/model/app_settings_dto.dart';

void main() {
  test('feature datasource owns account preference persistence', () async {
    final tool = _MemoryPreferencesDatasourceTool();
    final datasource = AccountPreferencesDatasource$Preferences(
      preferencesDatasourceTool: tool,
    );

    await datasource.saveGuestName('Guest_123456');

    expect(datasource.guestName, 'Guest_123456');
    expect(tool.values, hasLength(1));
  });

  test(
    'settings datasource owns keys, defaults and typed persistence',
    () async {
      final tool = _MemoryPreferencesDatasourceTool();
      final SettingsDatasource datasource = SettingsDatasource$Preferences(
        preferencesDatasourceTool: tool,
      );

      AppSettingsDto loaded = datasource.load();
      expect(loaded.sound, isTrue);
      expect(loaded.volume, 1);
      expect(loaded.animations, isTrue);
      expect(loaded.hints, isTrue);
      expect(loaded.xrayDefault, isFalse);
      expect(loaded.tutorialSeen, isFalse);

      const value = AppSettingsDto(
        sound: false,
        volume: .4,
        animations: false,
        hints: false,
        xrayDefault: true,
        tutorialSeen: true,
      );
      await datasource.save(value);

      loaded = datasource.load();
      expect(loaded.sound, value.sound);
      expect(loaded.volume, value.volume);
      expect(loaded.animations, value.animations);
      expect(loaded.hints, value.hints);
      expect(loaded.xrayDefault, value.xrayDefault);
      expect(loaded.tutorialSeen, value.tutorialSeen);
      expect(tool.values, hasLength(6));
    },
  );

  test(
    'online datasource owns JSON serialization and invalid-data fallback',
    () async {
      final tool = _MemoryPreferencesDatasourceTool();
      final OnlineSessionDatasource datasource =
          OnlineSessionDatasource$Preferences(preferencesDatasourceTool: tool);

      await datasource.saveSession(const {'code': 'ABCDE', 'player': 1});
      expect(datasource.loadSession(), const {'code': 'ABCDE', 'player': 1});
      expect(tool.values.values.single, isA<String>());

      tool.values[tool.values.keys.single] = '{broken';
      expect(datasource.loadSession(), isNull);
    },
  );
}

final class _MemoryPreferencesDatasourceTool
    implements PreferencesDatasourceTool {
  final Map<String, Object> values = {};

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  double? getDouble(String key) => values[key] as double?;

  @override
  int? getInt(String key) => values[key] as int?;

  @override
  Set<String> getKeys() => values.keys.toSet();

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<void> removeKey(String key) async {
    values.remove(key);
  }

  @override
  Future<void> setBool(String key, {required bool value}) async {
    values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    values[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
