import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/components/buttons/app_action_button.dart';
import 'package:four3/src/feature/components/fields/app_text_field.dart';
import 'package:four3/src/feature/components/progress/app_circular_progress_indicator.dart';
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
      expect(style?.fontWeight, FontWeight.w600);
    }
    expect(theme.textTheme.labelLarge?.fontSize, 14);
    expect(theme.textTheme.labelLarge?.fontWeight, FontWeight.w600);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(theme.textTheme.bodyMedium?.fontSize, 14);
  });

  testWidgets('icon buttons center content and share the pressed treatment', (
    tester,
  ) async {
    const Key standardButton = ValueKey<String>('standard-button');
    const Key standardIcon = ValueKey<String>('standard-icon');
    const Key outlinedButton = ValueKey<String>('outlined-button');
    const Key outlinedIcon = ValueKey<String>('outlined-icon');
    const Key stretchedButton = ValueKey<String>('stretched-button');
    const Key stretchedIcon = ValueKey<String>('stretched-icon');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Material(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: standardButton,
                  tooltip: 'Standard',
                  onPressed: () {},
                  icon: const Icon(Icons.close, key: standardIcon),
                ),
                IconButton.outlined(
                  key: outlinedButton,
                  tooltip: 'Outlined',
                  onPressed: () {},
                  icon: const Icon(Icons.refresh, key: outlinedIcon),
                ),
                SizedBox(
                  width: 120,
                  height: 44,
                  child: IconButton.outlined(
                    key: stretchedButton,
                    tooltip: 'Stretched',
                    onPressed: () {},
                    icon: const Icon(Icons.replay, key: stretchedIcon),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final (Key button, Key icon) in <(Key, Key)>[
      (standardButton, standardIcon),
      (outlinedButton, outlinedIcon),
      (stretchedButton, stretchedIcon),
    ]) {
      expect(
        tester.getCenter(find.byKey(icon)),
        tester.getCenter(find.byKey(button)),
      );
      final Size size = tester.getSize(find.byKey(button));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(tester.getSize(find.byKey(stretchedButton)).width, 120);

    final ButtonStyle style = AppTheme.light.iconButtonTheme.style!;
    expect(style.padding?.resolve(const <WidgetState>{}), EdgeInsets.zero);
    expect(style.alignment, Alignment.center);
    expect(style.splashFactory, InkRipple.splashFactory);
    expect(
      style.overlayColor?.resolve(const <WidgetState>{WidgetState.pressed}),
      isNot(Colors.transparent),
    );
    final OutlinedBorder? shape = style.shape?.resolve(const <WidgetState>{});
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppRadii.control),
    );
  });

  testWidgets('toggle keeps its platform geometry and changes value', (
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

    expect(tester.getSize(find.byType(AppToggle)), const Size(51, 44));
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
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: AppTextField(controller: controller, label: 'Email'),
        ),
      ),
    );

    expect(find.text('Email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'mail@example.com');
    expect(controller.text, 'mail@example.com');
  });

  testWidgets('text field visually separates a hint from entered text', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Material(
          child: AppTextField(
            controller: controller,
            label: 'Username',
            hintText: 'For example, player123',
          ),
        ),
      ),
    );

    TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, 'For example, player123');
    expect(field.decoration?.hintStyle?.color, const Color(0xFF8B9088));
    expect(field.decoration?.hintStyle?.fontSize, 16);
    expect(field.decoration?.hintStyle?.fontWeight, FontWeight.w400);
    expect(field.style?.color, AppColors.ink);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, isNull);
  });

  testWidgets('password field exposes helper, error and visibility state', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'secret-value');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: AppTextField(
            controller: controller,
            label: 'Password',
            helperText: 'At least 8 characters',
            obscureText: true,
            showPasswordToggle: true,
            autofillHints: const <String>[AutofillHints.password],
          ),
        ),
      ),
    );

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: AppTextField(
            controller: controller,
            label: 'Password',
            helperText: 'At least 8 characters',
            errorText: 'Password is too short',
          ),
        ),
      ),
    );
    expect(find.text('Password is too short'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsNothing);
  });

  testWidgets('loading action keeps the active primary treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Material(
          child: Center(
            child: AppActionButton(
              label: 'Connecting',
              onPressed: null,
              loading: true,
            ),
          ),
        ),
      ),
    );

    final FilledButton button = tester.widget(find.byType(FilledButton));
    expect(
      button.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppColors.accent,
    );
    expect(find.byType(AppCircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(FilledButton)).height, 48);
  });

  testWidgets('circular progress uses the compact app appearance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Material(
          child: Center(child: AppCircularProgressIndicator()),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(AppCircularProgressIndicator)),
      const Size.square(28),
    );
    final CircularProgressIndicator indicator = tester.widget(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNull);
    expect(indicator.backgroundColor, Colors.transparent);
    expect(indicator.color, AppColors.accent);
    expect(indicator.strokeWidth, 2.5);
    expect(indicator.strokeAlign, CircularProgressIndicator.strokeAlignInside);
    expect(indicator.strokeCap, StrokeCap.round);
  });

  testWidgets('circular progress forwards a determinate value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Material(
          child: Center(child: AppCircularProgressIndicator(value: .42)),
        ),
      ),
    );

    final CircularProgressIndicator indicator = tester.widget(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, .42);
  });
}
