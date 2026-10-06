import 'package:four3/src/feature/settings/data/model/app_settings_dto.dart';

abstract interface class SettingsDatasource {
  const new();

  AppSettingsDto load();
  Future<void> save(AppSettingsDto value);
}
