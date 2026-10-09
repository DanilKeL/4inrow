import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/modals/app_dialog.dart';

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
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final double transitionHeight = tester.getSize(transition).height;
    expect(transitionHeight, lessThan(expandedHeight));
    expect(transitionHeight, greaterThan(compactHeight));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Open details'), findsOneWidget);
    expect(find.text('Count 1'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
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
