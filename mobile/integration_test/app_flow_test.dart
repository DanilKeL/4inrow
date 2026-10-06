import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/main.dart' as app;
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/bloc/game_event.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_scene_view.dart';
import 'package:four3/src/feature/game/widget/game_shell.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('menu starts a game and a projected center tap stays centered', (
    tester,
  ) async {
    app.main();
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(GameShell).evaluate().isNotEmpty) break;
    }

    expect(find.byType(GameShell), findsOneWidget);
    final GameBloc bloc = GameRootScope.of(
      tester.element(find.byType(GameShell)),
    );
    for (var attempt = 0; attempt < 30 && bloc.data == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(bloc.data, isNotNull);
    await tester.pump(const Duration(milliseconds: 500));
    if (bloc.data?.phase != GamePhase.menu) {
      bloc.add(const GameEvent$Menu());
      await tester.pump(const Duration(milliseconds: 500));
    }

    final Object? buildException = tester.takeException();
    expect(buildException, isNull, reason: buildException?.toString());
    final List<String?> visibleTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .toList(growable: false);
    expect(
      find.text('Four in a row'),
      findsOneWidget,
      reason: 'Rendered texts: $visibleTexts; phase: ${bloc.data?.phase}',
    );
    await binding.takeScreenshot('menu-portrait');

    await tester.tap(find.text('Two players'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('New game'), findsOneWidget);
    await tester.tap(find.text('Start game'));
    await tester.pump(const Duration(seconds: 1));

    if (find.text('How to play').evaluate().isNotEmpty) {
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
    }

    expect(bloc.data?.phase, GamePhase.playing);
    await binding.takeScreenshot('local-game-empty');

    final Finder sceneFinder = find.byType(GameSceneView);
    final Size size = tester.getSize(sceneFinder);
    final Offset origin = tester.getTopLeft(sceneFinder);
    final double fit = math.max(1, .9 / (size.width / size.height));
    final fs.PerspectiveCamera camera = fs.PerspectiveCamera(
      fovRadiansY: 35 * math.pi / 180,
      position: vm.Vector3(7.4, 9.2, 9.3)..scale(fit),
      target: vm.Vector3(0, .25, 0),
      fovFar: 100,
    );
    final Offset center = camera.worldToScreen(vm.Vector3(0, .13, 0), size)!;
    await tester.tapAt(origin + center);
    await tester.pump(const Duration(seconds: 1));

    expect(bloc.data?.snapshot.history, hasLength(1));
    expect(bloc.data?.snapshot.history.single.x, 2);
    expect(bloc.data?.snapshot.history.single.y, 2);
    await binding.takeScreenshot('local-game-center-move');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Time is stopped.'), findsOneWidget);
    await tester.tap(find.text('Main menu'));
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('End the current game?').evaluate().isNotEmpty) {
      await tester.tap(find.text('Exit to menu'));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(bloc.data?.phase, GamePhase.menu);
    expect(find.text('Four in a row'), findsOneWidget);

    bloc.add(
      GameEvent$ReplaySaved(
        snapshot: GameEngine.replay(const [
          MoveCandidate(0, 0),
          MoveCandidate(4, 4),
          MoveCandidate(4, 0),
          MoveCandidate(0, 4),
          MoveCandidate(2, 2),
          MoveCandidate(2, 3),
          MoveCandidate(1, 4),
          MoveCandidate(3, 0),
          MoveCandidate(0, 2),
          MoveCandidate(4, 2),
          MoveCandidate(1, 1),
          MoveCandidate(3, 3),
        ]),
        names: const ['Player 1', 'Player 2'],
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await binding.takeScreenshot('game-filled');
    bloc.add(const GameEvent$ToggleXray());
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('game-xray');

    bloc.add(
      GameEvent$ReplaySaved(
        snapshot: GameEngine.replay(const [
          MoveCandidate(0, 0),
          MoveCandidate(0, 4),
          MoveCandidate(1, 0),
          MoveCandidate(1, 4),
          MoveCandidate(2, 0),
          MoveCandidate(2, 4),
          MoveCandidate(3, 0),
        ]),
        names: const ['Player 1', 'Player 2'],
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await binding.takeScreenshot('game-victory');
    expect(tester.takeException(), isNull);

    bloc.add(const GameEvent$Menu());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(LucideIcons.userRound).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('CURRENT PROFILE'), findsOneWidget);
    expect(find.text('Registration'), findsOneWidget);
    await binding.takeScreenshot('account-guest-portrait');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(LucideIcons.settings2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Move preview'), findsOneWidget);
    await binding.takeScreenshot('settings-portrait');
    expect(tester.takeException(), isNull);
  });
}
