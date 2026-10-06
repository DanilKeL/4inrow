import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF3F2EE);
  static const surface = Color(0xFFFAFAF7);
  static const graphite = Color(0xFF252724);
  static const ink = Color(0xFF252724);
  static const muted = Color(0xFF777A75);
  static const border = Color(0xFFDDDFD7);
  static const ivory = Color(0xFFF5F0E5);
  static const accent = Color(0xFF2955E7);
  static const success = Color(0xFF426B4A);
  static const danger = Color(0xFF9A3F35);
}

abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Manrope',
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'Manrope',
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      dividerColor: AppColors.border,
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0x99FFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
