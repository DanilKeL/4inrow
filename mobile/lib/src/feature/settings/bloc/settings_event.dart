import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';

sealed class SettingsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class SettingsEvent$Load extends SettingsEvent {
  const new();
}

final class SettingsEvent$Update extends SettingsEvent {
  const new(this.settings);

  final AppSettings settings;

  @override
  List<Object> get props => [settings];
}
