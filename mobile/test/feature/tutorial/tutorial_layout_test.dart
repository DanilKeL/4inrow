import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/modals/app_dialog.dart';
import 'package:four3/src/feature/tutorial/widget/tutorial_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTutorial(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SafeArea(child: TutorialView(loadVideos: false)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('portrait video stays below the lesson selector', (tester) async {
    await pumpTutorial(tester, const Size(390, 844));

    final Finder selector = find.byKey(const ValueKey('tutorial-selector'));
    final Rect lastTab = tester.getRect(
      find.descendant(of: selector, matching: find.byType(OutlinedButton)).last,
    );
    final Rect media = tester.getRect(
      find.byKey(const ValueKey('tutorial-media')),
    );
    expect(lastTab.bottom, lessThanOrEqualTo(media.top));
    final Size stage = tester.getSize(
      find.byKey(const ValueKey('tutorial-media-stage')),
    );
    expect(stage.width / stage.height, closeTo(2, .001));
  });

  testWidgets('landscape video stays to the right of the lesson selector', (
    tester,
  ) async {
    await pumpTutorial(tester, const Size(844, 390));

    final Rect selector = tester.getRect(
      find.byKey(const ValueKey('tutorial-selector')),
    );
    final Rect media = tester.getRect(
      find.byKey(const ValueKey('tutorial-media')),
    );
    expect(selector.right, lessThanOrEqualTo(media.left));
    final Size stage = tester.getSize(
      find.byKey(const ValueKey('tutorial-media-stage')),
    );
    expect(stage.width / stage.height, closeTo(2, .001));
  });

  for (final Size size in <Size>[
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('tutorial dialog fits ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppDialog<void>(
                  context: context,
                  titleBuilder: (context) => context.l10n.howToPlay,
                  wide: true,
                  builder: (_) => const TutorialView(loadVideos: false),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final Size tutorialSize = tester.getSize(find.byType(TutorialView));
      expect(tutorialSize.height, lessThan(size.height));
      if (size.height > size.width) {
        expect(tutorialSize.height, lessThan(600));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
