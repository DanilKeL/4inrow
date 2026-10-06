import 'package:four3/src/feature/settings/domain/model/app_settings.dart';

final class AppSettingsDto {
  const new({
    required this.sound,
    required this.volume,
    required this.animations,
    required this.hints,
    required this.xrayDefault,
    required this.tutorialSeen,
  });

  factory fromEntity(AppSettings entity) => AppSettingsDto(
    sound: entity.sound,
    volume: entity.volume,
    animations: entity.animations,
    hints: entity.hints,
    xrayDefault: entity.xrayDefault,
    tutorialSeen: entity.tutorialSeen,
  );

  final bool sound;
  final double volume;
  final bool animations;
  final bool hints;
  final bool xrayDefault;
  final bool tutorialSeen;

  AppSettings toEntity() => AppSettings(
    sound: sound,
    volume: volume,
    animations: animations,
    hints: hints,
    xrayDefault: xrayDefault,
    tutorialSeen: tutorialSeen,
  );
}
