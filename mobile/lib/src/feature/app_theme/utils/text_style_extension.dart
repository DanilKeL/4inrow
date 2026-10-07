import 'package:flutter/material.dart';

@immutable
final class AppTextStyleExtension
    extends ThemeExtension<AppTextStyleExtension> {
  const new({
    required this.display,
    required this.title,
    required this.headline,
    required this.body,
    required this.bodyStrong,
    required this.caption,
    required this.captionStrong,
    required this.micro,
    required this.button,
    required this.buttonSmall,
  });

  final TextStyle display;
  final TextStyle title;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle caption;
  final TextStyle captionStrong;
  final TextStyle micro;
  final TextStyle button;
  final TextStyle buttonSmall;

  @override
  AppTextStyleExtension copyWith({
    TextStyle? display,
    TextStyle? title,
    TextStyle? headline,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? caption,
    TextStyle? captionStrong,
    TextStyle? micro,
    TextStyle? button,
    TextStyle? buttonSmall,
  }) => AppTextStyleExtension(
    display: display ?? this.display,
    title: title ?? this.title,
    headline: headline ?? this.headline,
    body: body ?? this.body,
    bodyStrong: bodyStrong ?? this.bodyStrong,
    caption: caption ?? this.caption,
    captionStrong: captionStrong ?? this.captionStrong,
    micro: micro ?? this.micro,
    button: button ?? this.button,
    buttonSmall: buttonSmall ?? this.buttonSmall,
  );

  @override
  AppTextStyleExtension lerp(
    covariant ThemeExtension<AppTextStyleExtension>? other,
    double t,
  ) {
    if (other is! AppTextStyleExtension) return this;
    return AppTextStyleExtension(
      display: TextStyle.lerp(display, other.display, t) ?? display,
      title: TextStyle.lerp(title, other.title, t) ?? title,
      headline: TextStyle.lerp(headline, other.headline, t) ?? headline,
      body: TextStyle.lerp(body, other.body, t) ?? body,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t) ?? bodyStrong,
      caption: TextStyle.lerp(caption, other.caption, t) ?? caption,
      captionStrong:
          TextStyle.lerp(captionStrong, other.captionStrong, t) ??
          captionStrong,
      micro: TextStyle.lerp(micro, other.micro, t) ?? micro,
      button: TextStyle.lerp(button, other.button, t) ?? button,
      buttonSmall:
          TextStyle.lerp(buttonSmall, other.buttonSmall, t) ?? buttonSmall,
    );
  }
}
