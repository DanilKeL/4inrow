import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/app/locale_scope.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/modals/app_dialog.dart';
import 'package:four3/src/feature/settings/widget/settings_view.dart';

void main() {
  testWidgets('language picker exposes its value and opens every option', (
    tester,
  ) async {
    final key = GlobalKey<_LanguagePickerTestAppState>();
    await tester.pumpWidget(
      _LanguagePickerTestApp(key: key, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    final Finder button = find.byKey(
      const ValueKey<String>('language-picker-button'),
    );
    expect(tester.getSize(button).height, 44);
    final SemanticsNode buttonSemantics = tester.getSemantics(button);
    expect(buttonSemantics.label, 'Language: English');
    expect(buttonSemantics.flagsCollection.isButton, isTrue);
    expect(buttonSemantics.flagsCollection.isExpanded, Tristate.isFalse);

    await tester.tap(button);
    await tester.pumpAndSettle();

    for (final String tag in <String>[
      'system',
      'en',
      'ru',
      'es',
      'fr',
      'pt-BR',
      'de',
    ]) {
      expect(
        find.byKey(ValueKey<String>('language-option-$tag')),
        findsOneWidget,
      );
    }
    final SemanticsNode selectedSemantics = tester.getSemantics(
      find.byKey(const ValueKey<String>('language-option-en')),
    );
    expect(selectedSemantics.flagsCollection.isSelected, Tristate.isTrue);
  });

  testWidgets('language picker changes locale and restores system mode', (
    tester,
  ) async {
    final key = GlobalKey<_LanguagePickerTestAppState>();
    await tester.pumpWidget(
      _LanguagePickerTestApp(key: key, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('language-picker-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('language-option-es')));
    await tester.pumpAndSettle();

    expect(key.currentState!.locale, const Locale('es'));
    expect(find.text('Español'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('language-option-system')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('language-picker-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('language-option-system')),
    );
    await tester.pumpAndSettle();

    expect(key.currentState!.locale, isNull);
    expect(find.text('System'), findsOneWidget);
  });

  testWidgets(
    'switches between system and explicit locale when both resolve equally',
    (tester) async {
      final AppLocalizations russian = lookupAppLocalizations(
        const Locale('ru'),
      );
      final key = GlobalKey<_SystemLocalePickerTestAppState>();
      await tester.pumpWidget(_SystemLocalePickerTestApp(key: key));
      await tester.pumpAndSettle();

      expect(key.currentState!.locale, isNull);
      expect(find.text(russian.systemLanguage), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('language-picker-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('language-option-ru')),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.locale, const Locale('ru'));
      expect(find.text(russian.languageRussian), findsOneWidget);
      expect(find.text(russian.systemLanguage), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('language-picker-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('language-option-system')),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.locale, isNull);
      expect(find.text(russian.systemLanguage), findsOneWidget);
      expect(find.text(russian.languageRussian), findsNothing);
    },
  );

  testWidgets('an open dialog rebuilds its title when locale changes', (
    tester,
  ) async {
    final AppLocalizations french = lookupAppLocalizations(const Locale('fr'));
    final AppLocalizations russian = lookupAppLocalizations(const Locale('ru'));
    final key = GlobalKey<_LocalizedDialogTestAppState>();
    await tester.pumpWidget(_LocalizedDialogTestApp(key: key));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text(french.settings), findsOneWidget);
    expect(find.text(french.language), findsOneWidget);

    key.currentState!.setLocale(const Locale('ru'));
    await tester.pumpAndSettle();

    expect(find.text(russian.settings), findsOneWidget);
    expect(find.text(russian.language), findsOneWidget);
    expect(find.text(french.settings), findsNothing);
    expect(find.text(french.language), findsNothing);
  });

  for (final ({String name, Size screenSize, double pickerWidth}) scenario
      in <({String name, Size screenSize, double pickerWidth})>[
        (
          name: 'narrow portrait',
          screenSize: const Size(320, 568),
          pickerWidth: 160,
        ),
        (
          name: 'short landscape',
          screenSize: const Size(844, 390),
          pickerWidth: 190,
        ),
      ]) {
    testWidgets('language picker fits ${scenario.name}', (tester) async {
      tester.view.physicalSize = scenario.screenSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _LanguagePickerTestApp(
          initialLocale: const Locale.fromSubtags(
            languageCode: 'pt',
            countryCode: 'BR',
          ),
          pickerWidth: scenario.pickerWidth,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('language-picker-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Português (Brasil)'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}

class _LocalizedDialogTestApp extends StatefulWidget {
  const new({super.key});

  @override
  State<_LocalizedDialogTestApp> createState() =>
      _LocalizedDialogTestAppState();
}

class _LocalizedDialogTestAppState extends State<_LocalizedDialogTestApp> {
  Locale locale = const Locale('fr');

  void setLocale(Locale value) => setState(() => locale = value);

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: appSupportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAppDialog<void>(
            context: context,
            titleBuilder: (context) => context.l10n.settings,
            builder: (context) => Text(context.l10n.language),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

class _SystemLocalePickerTestApp extends StatefulWidget {
  const new({super.key});

  @override
  State<_SystemLocalePickerTestApp> createState() =>
      _SystemLocalePickerTestAppState();
}

class _SystemLocalePickerTestAppState
    extends State<_SystemLocalePickerTestApp> {
  Locale? locale;

  @override
  Widget build(BuildContext context) => AppLocaleScope(
    locale: locale,
    setLocale: (value) async => setState(() => locale = value),
    child: MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: appSupportedLocales,
      localeListResolutionCallback: (_, _) => const Locale('ru'),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final AppLocaleScope scope = AppLocaleScope.of(context);
            return Center(
              child: SizedBox(
                width: 220,
                child: AppLanguagePicker(
                  locale: scope.locale,
                  onChanged: scope.setLocale,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _LanguagePickerTestApp extends StatefulWidget {
  const new({required this.initialLocale, this.pickerWidth = 220, super.key});

  final Locale? initialLocale;
  final double pickerWidth;

  @override
  State<_LanguagePickerTestApp> createState() => _LanguagePickerTestAppState();
}

class _LanguagePickerTestAppState extends State<_LanguagePickerTestApp> {
  late Locale? locale = widget.initialLocale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    locale: locale ?? const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: appSupportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: widget.pickerWidth,
          child: AppLanguagePicker(
            locale: locale,
            onChanged: (value) async => setState(() => locale = value),
          ),
        ),
      ),
    ),
  );
}
