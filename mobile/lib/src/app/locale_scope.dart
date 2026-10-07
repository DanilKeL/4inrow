import 'package:flutter/material.dart';
import 'package:four3/src/feature/localization/data/datasource/app_locale_datasource.dart';

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
  new(this._datasource)
    : _locale = appLocaleFromTag(_datasource.loadLanguageTag());

  final AppLocaleDatasource _datasource;
  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    await _datasource.saveLanguageTag(locale?.toLanguageTag());
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

  static AppLocaleScope of(BuildContext context) {
    final AppLocaleScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    assert(scope != null, 'No AppLocaleScope found above this context.');
    if (scope == null) {
      throw StateError('No AppLocaleScope found above this context.');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(covariant AppLocaleScope oldWidget) =>
      locale != oldWidget.locale;
}
