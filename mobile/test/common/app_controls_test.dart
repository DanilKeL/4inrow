import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/fields/app_text_field.dart';
import 'package:four3/src/feature/components/selectors/app_segmented_control.dart';
import 'package:four3/src/feature/components/selectors/app_toggle.dart';

void main() {
  test('button variants use one shared typography scale', () {
    final ThemeData theme = AppTheme.light;
    final TextStyle? filled = theme.filledButtonTheme.style?.textStyle?.resolve(
      const <WidgetState>{},
    );
    final TextStyle? outlined = theme.outlinedButtonTheme.style?.textStyle
        ?.resolve(const <WidgetState>{});
    final TextStyle? text = theme.textButtonTheme.style?.textStyle?.resolve(
      const <WidgetState>{},
    );

    for (final TextStyle? style in <TextStyle?>[filled, outlined, text]) {
      expect(style?.fontFamily, 'Manrope');
      expect(style?.fontSize, 14);
      expect(style?.fontWeight, FontWeight.w700);
    }
    expect(theme.textTheme.labelLarge?.fontSize, 14);
    expect(theme.textTheme.labelLarge?.fontWeight, FontWeight.w700);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(theme.textTheme.bodyMedium?.fontSize, 14);
  });

  testWidgets('web toggle keeps its geometry and changes value', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) => Material(
            child: Center(
              child: AppToggle(
                value: value,
                semanticLabel: 'Animations',
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
    expect(semantics.label, 'Animations');
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
  });

  testWidgets('segmented control changes selected option', (tester) async {
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) => Material(
            child: AppSegmentedControl<int>(
              options: const [
                AppSegment(value: 1, label: 'First'),
                AppSegment(value: 2, label: 'Second'),
              ],
              selected: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Second'));
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
        theme: AppTheme.light,
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
