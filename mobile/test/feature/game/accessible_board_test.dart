import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/widget/game_scene_view.dart';

void main() {
  testWidgets('accessible board exposes 25 columns and disables full ones', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final GameSnapshot base = GameEngine.create();
    final GameSnapshot snapshot = GameSnapshot(
      board: base.board,
      heights: <int>[5, ...List<int>.filled(24, 0)],
      currentPlayer: Player.one,
      history: const <GameMove>[],
      status: GameStatus.playing,
      winner: null,
      winningLines: const <List<BoardPosition>>[],
    );
    final placements = <(int, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: SizedBox.square(
            dimension: 320,
            child: GameAccessibleBoardGrid(
              data: GameViewData(snapshot: snapshot, phase: GamePhase.playing),
              onPlace: (x, y) => placements.add((x, y)),
            ),
          ),
        ),
      ),
    );

    for (var y = 0; y < GameEngine.size; y++) {
      for (var x = 0; x < GameEngine.size; x++) {
        expect(
          find.byKey(ValueKey<String>('board-column-$x-$y')),
          findsOneWidget,
        );
      }
    }
    final SemanticsNode full = tester.getSemantics(
      find.byKey(const ValueKey<String>('board-column-0-0')),
    );
    expect(full.label, contains('5 pieces'));
    expect(full.flagsCollection.isEnabled, Tristate.isFalse);
    expect(full.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(placements, isEmpty);

    final SemanticsNode open = tester.getSemantics(
      find.byKey(const ValueKey<String>('board-column-4-4')),
    );
    expect(open.label, contains('0 pieces'));
    expect(open.flagsCollection.isEnabled, Tristate.isTrue);
    tester.semantics.tap(find.semantics.byLabel('Column 5, 5, 0 pieces'));
    await tester.pump();
    expect(placements, <(int, int)>[(4, 4)]);
    semantics.dispose();
  });
}
