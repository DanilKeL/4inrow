import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/matchmaking/widget/online_setup_view.dart';

void main() {
  testWidgets('search icon moves along its 1.8 second orbit', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: QuickSearchOrbitIcon())),
    );
    final Finder finder = find.byKey(const ValueKey('quick-search-orbit'));
    final List<double> first = List<double>.of(
      tester.widget<Transform>(finder).transform.storage,
    );

    await tester.pump(const Duration(milliseconds: 450));
    final List<double> quarter = List<double>.of(
      tester.widget<Transform>(finder).transform.storage,
    );

    expect(quarter, isNot(orderedEquals(first)));
    await tester.pump(const Duration(milliseconds: 1350));
    final List<double> completed = tester
        .widget<Transform>(finder)
        .transform
        .storage;
    expect(completed[12], closeTo(first[12], .01));
    expect(completed[13], closeTo(first[13], .01));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('system reduced motion keeps the search icon still', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(child: QuickSearchOrbitIcon()),
        ),
      ),
    );
    final Finder finder = find.byKey(const ValueKey('quick-search-orbit'));
    final List<double> first = List<double>.of(
      tester.widget<Transform>(finder).transform.storage,
    );

    await tester.pump(const Duration(milliseconds: 900));

    final List<double> after = tester
        .widget<Transform>(finder)
        .transform
        .storage;
    expect(after, orderedEquals(first));
  });
}
