import 'package:flutter/material.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef LocaleSetter = Future<void> Function(Locale? locale);

const List<Locale> appSupportedLocales = <Locale>[
  Locale('en'),
  Locale('ru'),
  Locale('es'),
  Locale('fr'),
  Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
  Locale('de'),
];

Locale? appLocaleFromTag(String? tag) => switch (tag) {
  'de' => const Locale('de'),
  'en' => const Locale('en'),
  'es' => const Locale('es'),
  'fr' => const Locale('fr'),
  'pt-BR' => const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
  'ru' => const Locale('ru'),
  _ => null,
};

Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final Locale locale in preferred ?? const <Locale>[]) {
    for (final Locale candidate in supported) {
      if (candidate.languageCode == locale.languageCode &&
          (candidate.countryCode == null ||
              candidate.countryCode == locale.countryCode)) {
        return candidate;
      }
    }
  }
  return const Locale('en');
}

final class LocaleController extends ChangeNotifier {
  new(this._preferences)
    : _locale = appLocaleFromTag(_preferences.getString(preferenceKey));

  static const String preferenceKey = 'settings.locale';

  final SharedPreferences _preferences;
  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    if (locale == null) {
      await _preferences.remove(preferenceKey);
    } else {
      await _preferences.setString(preferenceKey, locale.toLanguageTag());
    }
  }
}

class AppLocaleScope extends InheritedWidget {
  const new({
    required this.locale,
    required this.setLocale,
    required super.child,
    super.key,
  });

  final Locale? locale;
  final LocaleSetter setLocale;

  static AppLocaleScope of(BuildContext context) =>
      context.inheritedOf<AppLocaleScope>();

  @override
  bool updateShouldNotify(covariant AppLocaleScope oldWidget) =>
      locale != oldWidget.locale;
}
