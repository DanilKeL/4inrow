import 'package:flutter/material.dart';
import 'package:four3/src/feature/app_theme/utils/color_theme_extension.dart';
import 'package:four3/src/feature/app_theme/utils/text_style_extension.dart';

extension AppThemeContextExtension on BuildContext {
  ThemeData get theme => Theme.of(this);

  AppColorThemeExtension get colors =>
      theme.extension<AppColorThemeExtension>()!;

  AppTextStyleExtension get textStyle =>
      theme.extension<AppTextStyleExtension>()!;
}
