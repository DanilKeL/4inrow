import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/tutorial/widget/tutorial_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTutorial(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SafeArea(child: TutorialView(loadVideos: false))),
      ),
    );
    await tester.pump();
  }

  testWidgets('portrait video stays below the lesson selector', (tester) async {
    await pumpTutorial(tester, const Size(390, 844));

    final Rect selector = tester.getRect(
      find.byKey(const ValueKey('tutorial-selector')),
    );
    final Rect media = tester.getRect(
      find.byKey(const ValueKey('tutorial-media')),
    );
    expect(selector.bottom, lessThanOrEqualTo(media.top));
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
  });
}
