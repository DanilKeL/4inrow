import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/app/locale_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const List<String> localeFiles = <String>[
    'app_ru.arb',
    'app_es.arb',
    'app_fr.arb',
    'app_pt.arb',
    'app_pt_BR.arb',
    'app_de.arb',
  ];

  test('all ARB catalogs have the canonical keys and placeholders', () {
    final Map<String, dynamic> canonical = _readArb('app_en.arb');
    final Set<String> canonicalKeys = canonical.keys.toSet();

    for (final String file in localeFiles) {
      final Map<String, dynamic> catalog = _readArb(file);
      expect(catalog.keys.toSet(), canonicalKeys, reason: file);
      for (final String key in canonicalKeys.where(
        (key) => !key.startsWith('@'),
      )) {
        expect(catalog[key], isA<String>(), reason: '$file: $key');
        expect(
          (catalog[key] as String).trim(),
          isNotEmpty,
          reason: '$file: $key',
        );
        final Set<String> expected = _placeholderNames(canonical, key);
        final Set<String> actual = _placeholderNames(catalog, key);
        expect(actual, expected, reason: '$file: $key');
        expect(
          (catalog[key] as String).contains('plural'),
          (canonical[key] as String).contains('plural'),
          reason: '$file: $key',
        );
      }
    }
  });

  test('Russian catalog keeps the copy verified against the legacy UI', () {
    final Map<String, dynamic> catalog = _readArb('app_ru.arb');
    final List<String> keys =
        catalog.keys.where((key) => !key.startsWith('@')).toList()..sort();
    final String normalized = keys
        .map((key) => '$key\u0000${catalog[key]}\u0000')
        .join();

    expect(_fnv1a32(utf8.encode(normalized)), 0xa1175c9d);
  });

  test('the app exposes exactly the six requested locales', () {
    expect(
      appSupportedLocales.map((locale) => locale.toLanguageTag()),
      <String>['en', 'ru', 'es', 'fr', 'pt-BR', 'de'],
    );
  });

  test(
    'locale tags restore and unsupported languages fall back to English',
    () {
      for (final Locale locale in appSupportedLocales) {
        expect(appLocaleFromTag(locale.toLanguageTag()), locale);
      }
      expect(appLocaleFromTag(null), isNull);
      expect(appLocaleFromTag('it'), isNull);
      expect(
        resolveAppLocale(const <Locale>[Locale('it')], appSupportedLocales),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const <Locale>[
          Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
        ], appSupportedLocales),
        const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
      );
    },
  );

  test(
    'locale controller persists manual choice and clears system mode',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final LocaleController controller = LocaleController(preferences);
      expect(controller.locale, isNull);

      await controller.setLocale(
        const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
      );
      expect(preferences.getString(LocaleController.preferenceKey), 'pt-BR');
      expect(LocaleController(preferences).locale?.toLanguageTag(), 'pt-BR');

      await controller.setLocale(null);
      expect(preferences.containsKey(LocaleController.preferenceKey), isFalse);
      controller.dispose();
    },
  );

  for (final Locale locale in appSupportedLocales) {
    testWidgets('${locale.toLanguageTag()} loads localized Material widgets', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: appSupportedLocales,
          home: Builder(
            builder: (context) {
              final AppLocalizations strings = AppLocalizations.of(context);
              return Scaffold(
                body: Column(
                  children: <Widget>[
                    Text(strings.gameName),
                    Text(strings.moves(0)),
                    Text(strings.moves(1)),
                    Text(strings.moves(5)),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Map<String, dynamic> _readArb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholderNames(Map<String, dynamic> arb, String key) {
  final Object? metadata = arb['@$key'];
  if (metadata is! Map<String, dynamic>) return const <String>{};
  final Object? placeholders = metadata['placeholders'];
  if (placeholders is! Map<String, dynamic>) return const <String>{};
  return placeholders.keys.toSet();
}

int _fnv1a32(List<int> bytes) {
  int hash = 0x811c9dc5;
  for (final int byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash;
}
