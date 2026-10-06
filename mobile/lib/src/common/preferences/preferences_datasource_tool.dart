import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PreferencesDatasourceTool {
  const new();

  String? getString(String key);
  int? getInt(String key);
  double? getDouble(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> setDouble(String key, double value);
  Future<void> setBool(String key, {required bool value});
  Future<void> removeKey(String key);
  Set<String> getKeys();
}

final class PreferencesDatasourceTool$Shared
    implements PreferencesDatasourceTool {
  const new({required this.sharedPreferences});

  final SharedPreferences sharedPreferences;

  @override
  bool? getBool(String key) => sharedPreferences.getBool(key);

  @override
  double? getDouble(String key) => sharedPreferences.getDouble(key);

  @override
  int? getInt(String key) => sharedPreferences.getInt(key);

  @override
  Set<String> getKeys() => sharedPreferences.getKeys();

  @override
  String? getString(String key) => sharedPreferences.getString(key);

  @override
  Future<void> removeKey(String key) async {
    await sharedPreferences.remove(key);
  }

  @override
  Future<void> setBool(String key, {required bool value}) async {
    await sharedPreferences.setBool(key, value);
  }

  @override
  Future<void> setDouble(String key, double value) async {
    await sharedPreferences.setDouble(key, value);
  }

  @override
  Future<void> setInt(String key, int value) async {
    await sharedPreferences.setInt(key, value);
  }

  @override
  Future<void> setString(String key, String value) async {
    await sharedPreferences.setString(key, value);
  }
}
