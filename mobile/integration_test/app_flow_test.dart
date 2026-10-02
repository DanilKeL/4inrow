import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/main.dart' as app;
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_scene_view.dart';
import 'package:four3/src/feature/game/widget/game_shell.dart';
import 'package:integration_test/integration_test.dart';
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
      find.text('Четыре в ряд'),
      findsOneWidget,
      reason: 'Rendered texts: $visibleTexts; phase: ${bloc.data?.phase}',
    );
    await binding.takeScreenshot('menu-portrait');

    await tester.tap(find.text('Вдвоём'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Новая игра'), findsOneWidget);
    await tester.tap(find.text('Начать игру'));
    await tester.pump(const Duration(seconds: 1));

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
  });
}
