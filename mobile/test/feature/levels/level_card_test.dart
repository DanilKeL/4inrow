import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';
import 'package:four3/src/feature/levels/widget/levels_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  const GameLevel level = GameLevel(
    id: 3,
    chapter: LevelChapter.firstSteps,
    preset: [],
  );

  testWidgets('current level has a non-color marker and selected semantics', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _App(
        child: LevelCard(
          level: level,
          state: LevelCardState.current,
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.play), findsOneWidget);
    final SemanticsNode semantics = tester.getSemantics(find.byType(LevelCard));
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
    await tester.tap(find.byType(LevelCard));
    expect(taps, 1);
  });

  testWidgets('completed level shows its result and checkmark', (tester) async {
    await tester.pumpWidget(
      const _App(
        child: LevelCard(
          level: level,
          record: 4,
          state: LevelCardState.completed,
          onTap: _noop,
        ),
      ),
    );

    expect(find.text('Record: 4 moves'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  testWidgets('available levels remain actionable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _App(
        child: LevelCard(
          level: level,
          state: LevelCardState.available,
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.lock), findsNothing);
    final SemanticsNode semantics = tester.getSemantics(find.byType(LevelCard));
    expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);
    await tester.tap(find.byType(LevelCard));
    expect(taps, 1);
  });

  testWidgets('current level content fits the compact grid tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _App(
        child: SizedBox(
          height: 56,
          child: LevelCard(
            level: level,
            state: LevelCardState.current,
            onTap: _noop,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

class _App extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Material(
      child: Center(child: SizedBox(width: 220, child: child)),
    ),
  );
}
