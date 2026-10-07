import 'package:flutter/material.dart';
import 'package:four3/src/feature/app_theme/utils/color_theme_extension.dart';
import 'package:four3/src/feature/app_theme/utils/text_style_extension.dart';

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
  static const controlInactive = Color(0xFFD9DDCF);
  static const controlBorder = Color(0xFFDCE0D4);
}

abstract final class AppTheme {
  static ThemeData get light {
    const ColorScheme scheme = ColorScheme.light(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    );
    const AppColorThemeExtension colors = AppColorThemeExtension(
      background: AppColors.background,
      surface: AppColors.surface,
      ink: AppColors.ink,
      muted: AppColors.muted,
      border: AppColors.border,
      ivory: AppColors.ivory,
      accent: AppColors.accent,
      success: AppColors.success,
      danger: AppColors.danger,
      controlInactive: AppColors.controlInactive,
      controlBorder: AppColors.controlBorder,
    );
    const AppTextStyleExtension textStyle = AppTextStyleExtension(
      display: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
        color: AppColors.ink,
      ),
      title: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      headline: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      body: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        color: AppColors.ink,
      ),
      bodyStrong: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      caption: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        color: AppColors.muted,
      ),
      captionStrong: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      micro: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 9,
        color: AppColors.muted,
      ),
      button: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: .1,
        height: 1.2,
        color: AppColors.ink,
      ),
      buttonSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: AppColors.ink,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: const [colors, textStyle],
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Manrope',
      textTheme: ThemeData.light().textTheme
          .copyWith(
            displayLarge: textStyle.display,
            titleLarge: textStyle.title,
            titleMedium: textStyle.headline,
            titleSmall: textStyle.bodyStrong.copyWith(fontSize: 14),
            bodyLarge: textStyle.body.copyWith(fontSize: 16),
            bodyMedium: textStyle.body.copyWith(fontSize: 14),
            bodySmall: textStyle.caption.copyWith(fontSize: 12),
            labelLarge: textStyle.button,
            labelMedium: textStyle.captionStrong.copyWith(fontSize: 12),
            labelSmall: textStyle.captionStrong,
          )
          .apply(
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
          textStyle: textStyle.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: textStyle.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: textStyle.button,
        ),
      ),
    );
  }
}
