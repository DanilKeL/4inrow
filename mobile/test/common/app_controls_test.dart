import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/widget/app_controls.dart';

void main() {
  testWidgets('web toggle keeps its geometry and changes value', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Material(
            child: Center(
              child: AppToggle(
                value: value,
                semanticLabel: 'Анимации',
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppToggle)), const Size(48, 44));
    await tester.tap(find.byType(AppToggle));
    await tester.pump(const Duration(milliseconds: 200));
    expect(value, isTrue);
    final SemanticsNode semantics = tester.getSemantics(find.byType(AppToggle));
    expect(semantics.label, 'Анимации');
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
  });

  testWidgets('segmented control changes selected option', (tester) async {
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Material(
            child: AppSegmentedControl<int>(
              options: const [
                AppSegment(value: 1, label: 'Первый'),
                AppSegment(value: 2, label: 'Второй'),
              ],
              selected: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Второй'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(selected, 2);
  });

  testWidgets('text field renders an external label and accepts input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: AppTextField(controller: controller, label: 'Email'),
        ),
      ),
    );

    expect(find.text('Email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'mail@example.com');
    expect(controller.text, 'mail@example.com');
  });
}
