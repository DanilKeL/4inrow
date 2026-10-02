import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/main.dart' as app;
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/widget/game_root_scope.dart';
import 'package:four3/src/feature/game/widget/game_shell.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures the view popover in both orientations', (tester) async {
    app.main();
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(GameShell).evaluate().isNotEmpty) break;
    }
    final GameBloc bloc = GameRootScope.of(
      tester.element(find.byType(GameShell)),
    );
    for (var attempt = 0; attempt < 30 && bloc.data == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(milliseconds: 500));
    if (bloc.data?.phase != GamePhase.menu) {
      bloc.add(const GameEvent$Menu());
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.tap(find.text('Вдвоём'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Начать игру'));
    await tester.pump(const Duration(seconds: 1));
    if (find.text('Как играть').evaluate().isNotEmpty) {
      await tester.tap(find.text('Начать'));
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(find.text('Вид'));
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('view-popover-portrait');
    await tester.tap(find.byTooltip('Закрыть меню вида'));
    await tester.pump(const Duration(milliseconds: 300));

    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.layers3).first);
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('view-popover-landscape');
  });
}
