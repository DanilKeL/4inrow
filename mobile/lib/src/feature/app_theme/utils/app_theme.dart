import 'package:flutter/material.dart';
import 'package:four3/src/feature/app_theme/utils/color_theme_extension.dart';
import 'package:four3/src/feature/app_theme/utils/text_style_extension.dart';

abstract final class AppColors {
  static const background = Color(0xFFF3F2EE);
  static const surface = Color(0xFFFAFAF7);
  static const graphite = Color(0xFF252724);
  static const ink = Color(0xFF252724);
  static const muted = Color(0xFF62665F);
  static const tertiary = Color(0xFF7D817A);
  static const border = Color(0xFFDDDFD7);
  static const ivory = Color(0xFFF5F0E5);
  static const accent = Color(0xFF2955E7);
  static const accentSubtle = Color(0x172955E7);
  static const success = Color(0xFF426B4A);
  static const danger = Color(0xFF9A3F35);
  static const controlInactive = Color(0xFFD9DDCF);
  static const controlBorder = Color(0xFFDCE0D4);
  static const disabledSurface = Color(0xFFE9EBE5);
  static const disabledText = Color(0xFF8A8E86);
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadii {
  static const chip = 10.0;
  static const control = 12.0;
  static const card = 16.0;
  static const modal = 24.0;
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
      tertiary: AppColors.tertiary,
      border: AppColors.border,
      ivory: AppColors.ivory,
      accent: AppColors.accent,
      accentSubtle: AppColors.accentSubtle,
      success: AppColors.success,
      danger: AppColors.danger,
      controlInactive: AppColors.controlInactive,
      controlBorder: AppColors.controlBorder,
      disabledSurface: AppColors.disabledSurface,
      disabledText: AppColors.disabledText,
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
        height: 27 / 22,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      headline: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 17,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      body: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        height: 1.375,
        color: AppColors.ink,
      ),
      bodyStrong: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        height: 20 / 15,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      caption: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        height: 18 / 13,
        color: AppColors.muted,
      ),
      captionStrong: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        height: 4 / 3,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      micro: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 9,
        height: 14 / 11,
        color: AppColors.muted,
      ),
      button: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: .1,
        height: 1.2,
        color: AppColors.ink,
      ),
      buttonSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 11,
        fontWeight: FontWeight.w600,
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
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.modal)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0x99FFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: textStyle.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: textStyle.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: textStyle.button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          iconSize: 22,
          padding: EdgeInsets.zero,
          alignment: Alignment.center,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          overlayColor: AppColors.accentSubtle,
          splashFactory: InkRipple.splashFactory,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.controlInactive,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accentSubtle,
      ),
    );
  }
}
