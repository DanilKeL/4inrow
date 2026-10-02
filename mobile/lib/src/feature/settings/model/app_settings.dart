import 'package:equatable/equatable.dart';

final class AppSettings extends Equatable {
  const new({
    this.sound = true,
    this.volume = 1,
    this.animations = true,
    this.hints = true,
    this.xrayDefault = false,
    this.tutorialSeen = false,
  });

  final bool sound;
  final double volume;
  final bool animations;
  final bool hints;
  final bool xrayDefault;
  final bool tutorialSeen;

  AppSettings copyWith({
    bool? sound,
    double? volume,
    bool? animations,
    bool? hints,
    bool? xrayDefault,
    bool? tutorialSeen,
  }) => AppSettings(
    sound: sound ?? this.sound,
    volume: (volume ?? this.volume).clamp(0, 1),
    animations: animations ?? this.animations,
    hints: hints ?? this.hints,
    xrayDefault: xrayDefault ?? this.xrayDefault,
    tutorialSeen: tutorialSeen ?? this.tutorialSeen,
  );

  @override
  List<Object> get props => [
    sound,
    volume,
    animations,
    hints,
    xrayDefault,
    tutorialSeen,
  ];
}
