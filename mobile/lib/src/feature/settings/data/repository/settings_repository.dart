import 'package:four3/src/feature/settings/data/datasource/settings_datasource.dart';
import 'package:four3/src/feature/settings/data/model/app_settings_dto.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:four3/src/feature/settings/domain/repository/settings_repository.dart';

final class SettingsRepository$Local implements SettingsRepository {
  const new({required this.datasource});

  final SettingsDatasource datasource;

  @override
  AppSettings load() => datasource.load().toEntity();

  @override
  Future<void> save(AppSettings value) =>
      datasource.save(AppSettingsDto.fromEntity(value));
}
