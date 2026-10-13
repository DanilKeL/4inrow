import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/modals/app_dialog.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('dialog flow changes content in place and returns with back', (
    tester,
  ) async {
    final ValueNotifier<bool> details = ValueNotifier<bool>(false);
    addTearDown(details.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showAppDialog<void>(
                  context: context,
                  listenable: details,
                  onBackBuilder: (_) =>
                      details.value ? () => details.value = false : null,
                  titleBuilder: (_) => details.value ? 'Details' : 'Account',
                  builder: (_) => AppDialogPageTransition(
                    showSecond: details.value,
                    firstChild: _RememberingPage(
                      onOpen: () => details.value = true,
                    ),
                    secondChild: const SizedBox(
                      height: 320,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text('Details content'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final Finder transition = find.byType(AppDialogPageTransition);
    final double compactHeight = tester.getSize(transition).height;

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    final double expandedHeight = tester.getSize(transition).height;

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Details content'), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final double transitionHeight = tester.getSize(transition).height;
    expect(transitionHeight, lessThan(expandedHeight));
    expect(transitionHeight, greaterThan(compactHeight));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Open details'), findsOneWidget);
    expect(find.text('Count 1'), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
  });

  testWidgets('dialog returns focus to its opener', (tester) async {
    final FocusNode opener = FocusNode();
    addTearDown(opener.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              focusNode: opener,
              onPressed: () => showAppDialog<void>(
                context: context,
                titleBuilder: (_) => 'Dialog',
                builder: (_) => const Text('Body'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    opener.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(opener.hasFocus, isTrue);
  });

  testWidgets('backdrop dismiss does not tap the control below it', (
    tester,
  ) async {
    var underlyingTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: TextButton(
                    onPressed: () => underlyingTaps++,
                    child: const Text('Under dialog'),
                  ),
                ),
                Center(
                  child: FilledButton(
                    onPressed: () => showAppDialog<void>(
                      context: context,
                      titleBuilder: (_) => 'Dialog',
                      builder: (_) => const SizedBox(
                        height: 80,
                        child: Text('Dialog body'),
                      ),
                    ),
                    child: const Text('Open dialog'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Dialog body'), findsNothing);
    expect(underlyingTaps, 0);
  });

  testWidgets('dialog remains scrollable with keyboard and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 220),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                titleBuilder: (_) => 'Long dialog title',
                builder: (_) => const Column(
                  children: [
                    TextField(decoration: InputDecoration(labelText: 'One')),
                    SizedBox(height: 16),
                    TextField(decoration: InputDecoration(labelText: 'Two')),
                    SizedBox(height: 16),
                    TextField(decoration: InputDecoration(labelText: 'Three')),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Long dialog title'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}

class _RememberingPage extends StatefulWidget {
  const new({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_RememberingPage> createState() => _RememberingPageState();
}

class _RememberingPageState extends State<_RememberingPage> {
  int count = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 100,
    child: Column(
      children: [
        Text('Count $count'),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() => count++),
                child: const Text('Increment'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: widget.onOpen,
                child: const Text('Open details'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
