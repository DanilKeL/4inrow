import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('raycast selects every projected column in all camera views', (
    _,
  ) async {
    final controller = GameSceneController();
    addTearDown(controller.dispose);
    await controller.initialize();
    final GameSnapshot empty = GameEngine.create();
    controller.sync(
      snapshot: empty,
      xray: false,
      layers: const <int>[0, 1, 2, 3, 4],
      animations: false,
    );

    const List<Size> viewports = [Size(390, 620), Size(760, 390)];
    for (final Size viewport in viewports) {
      for (final CameraView view in CameraView.values) {
        final fs.PerspectiveCamera camera = _camera(view, viewport);
        for (var y = 0; y < 5; y++) {
          for (var x = 0; x < 5; x++) {
            final Offset point = camera.worldToScreen(
              vm.Vector3(
                (x - 2) * GameSceneController.spacing,
                .13,
                (y - 2) * GameSceneController.spacing,
              ),
              viewport,
            )!;
            expect(controller.pick(camera.screenPointToRay(point, viewport)), (
              x: x,
              y: y,
            ), reason: '$viewport · $view must pick projected column ($x, $y)');
          }
        }
      }
    }
  });

  testWidgets('an occupied center column wins over columns in front of it', (
    _,
  ) async {
    final controller = GameSceneController();
    addTearDown(controller.dispose);
    await controller.initialize();
    final GameSnapshot snapshot = GameEngine.replay(const <MoveCandidate>[
      MoveCandidate(2, 2),
    ]);
    controller.sync(
      snapshot: snapshot,
      xray: false,
      layers: const <int>[0, 1, 2, 3, 4],
      animations: false,
    );

    const Size portrait = Size(390, 620);
    final fs.PerspectiveCamera camera = _camera(
      CameraView.perspective,
      portrait,
    );
    final Offset center = camera.worldToScreen(
      vm.Vector3(0, .13 + GameSceneController.step, 0),
      portrait,
    )!;

    expect(controller.pick(camera.screenPointToRay(center, portrait)), (
      x: 2,
      y: 2,
    ));
  });
}

fs.PerspectiveCamera _camera(CameraView view, Size size) {
  final double fit = math.max(1, .9 / (size.width / size.height));
  final vm.Vector3 position = switch (view) {
    CameraView.perspective => vm.Vector3(7.4, 9.2, 9.3),
    CameraView.top => vm.Vector3(0, 13.7, .035),
    CameraView.front => vm.Vector3(0, 5.6, 12.8),
  }..scale(fit);
  return fs.PerspectiveCamera(
    fovRadiansY: 35 * math.pi / 180,
    position: position,
    target: vm.Vector3(0, .25, 0),
    up: view == CameraView.top ? vm.Vector3(0, 0, 1) : vm.Vector3(0, 1, 0),
    fovFar: 100,
  );
}
