import 'package:flutter/material.dart';

@immutable
final class AppColorThemeExtension
    extends ThemeExtension<AppColorThemeExtension> {
  const new({
    required this.background,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.border,
    required this.ivory,
    required this.accent,
    required this.success,
    required this.danger,
    required this.controlInactive,
    required this.controlBorder,
  });

  final Color background;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color border;
  final Color ivory;
  final Color accent;
  final Color success;
  final Color danger;
  final Color controlInactive;
  final Color controlBorder;

  @override
  AppColorThemeExtension copyWith({
    Color? background,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? border,
    Color? ivory,
    Color? accent,
    Color? success,
    Color? danger,
    Color? controlInactive,
    Color? controlBorder,
  }) => AppColorThemeExtension(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    ivory: ivory ?? this.ivory,
    accent: accent ?? this.accent,
    success: success ?? this.success,
    danger: danger ?? this.danger,
    controlInactive: controlInactive ?? this.controlInactive,
    controlBorder: controlBorder ?? this.controlBorder,
  );

  @override
  AppColorThemeExtension lerp(
    covariant ThemeExtension<AppColorThemeExtension>? other,
    double t,
  ) {
    if (other is! AppColorThemeExtension) return this;
    return AppColorThemeExtension(
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      border: Color.lerp(border, other.border, t) ?? border,
      ivory: Color.lerp(ivory, other.ivory, t) ?? ivory,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      success: Color.lerp(success, other.success, t) ?? success,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      controlInactive:
          Color.lerp(controlInactive, other.controlInactive, t) ??
          controlInactive,
      controlBorder:
          Color.lerp(controlBorder, other.controlBorder, t) ?? controlBorder,
    );
  }
}
