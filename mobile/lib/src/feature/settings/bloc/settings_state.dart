import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';

sealed class SettingsState extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class SettingsState$Initial extends SettingsState {
  const new();
}

final class SettingsState$Ready extends SettingsState {
  const new(this.settings);

  final AppSettings settings;

  @override
  List<Object> get props => [settings];
}

final class SettingsState$Failure extends SettingsState {
  const new();
}
