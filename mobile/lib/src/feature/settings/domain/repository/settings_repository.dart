import 'package:four3/src/feature/settings/domain/model/app_settings.dart';

abstract interface class SettingsRepository {
  const new();

  AppSettings load();
  Future<void> save(AppSettings value);
}
