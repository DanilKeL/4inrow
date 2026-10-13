import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';
import 'package:four3/src/feature/game/scene/victory_camera.dart';
import 'package:four3/src/feature/game/widget/game_scene_view.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('reset framing keeps the full board inside narrow viewports', () {
    for (final Size viewport in const <Size>[Size(320, 456), Size(402, 580)]) {
      final GameCameraFraming framing = gameCameraResetFraming(
        view: CameraView.perspective,
        viewport: viewport,
        demo: false,
      );
      final fs.PerspectiveCamera camera = fs.PerspectiveCamera(
        fovRadiansY: 35 * math.pi / 180,
        position: framing.position,
        target: framing.target,
        up: vm.Vector3(0, 1, 0),
        fovFar: 100,
      );

      double minX = double.infinity;
      double maxX = double.negativeInfinity;
      double minY = double.infinity;
      double maxY = double.negativeInfinity;
      for (final vm.Vector3 worldPoint in gameBoardFramingEnvelope()) {
        final Offset point = camera.worldToScreen(worldPoint, viewport)!;
        minX = math.min(minX, point.dx);
        maxX = math.max(maxX, point.dx);
        minY = math.min(minY, point.dy);
        maxY = math.max(maxY, point.dy);
      }
      final String bounds = 'bounds: $minX, $maxX, $minY, $maxY';
      expect(minX, greaterThanOrEqualTo(8), reason: bounds);
      expect(maxX, lessThanOrEqualTo(viewport.width - 8), reason: bounds);
      expect(minY, greaterThanOrEqualTo(8), reason: bounds);
      expect(maxY, lessThanOrEqualTo(viewport.height - 8), reason: bounds);
    }
  });

  test(
    'active-game reset changes nominal distance by at most three percent',
    () {
      const Size viewport = Size(320, 456);
      final GameCameraFraming framing = gameCameraResetFraming(
        view: CameraView.perspective,
        viewport: viewport,
        demo: false,
      );
      final double aspectFit = math.max(
        1,
        .9 / ((viewport.width - 32) / viewport.height),
      );
      final vm.Vector3 nominalPosition = vm.Vector3(7.4, 9.2, 9.3)
        ..scale(aspectFit * .84);
      final double nominalDistance =
          (nominalPosition - vm.Vector3(0, -.15, 0)).length;
      final double actualDistance = (framing.position - framing.target).length;

      expect(actualDistance, greaterThanOrEqualTo(nominalDistance));
      expect(actualDistance, lessThanOrEqualTo(nominalDistance * 1.03 + .0001));
    },
  );

  test(
    'menu preview is about seven percent smaller than the current scale',
    () {
      const Size viewport = Size(390, 300);
      final GameCameraFraming framing = gameCameraResetFraming(
        view: CameraView.perspective,
        viewport: viewport,
        demo: true,
      );
      final vm.Vector3 previousPosition = vm.Vector3(8.7, 7.25, 9.8)
        ..scale(.82);
      final double previousDistance =
          (previousPosition - vm.Vector3(0, -.35, 0)).length;
      final double nextDistance = (framing.position - framing.target).length;

      expect(nextDistance / previousDistance, closeTo(.88 / .82, .002));
    },
  );

  test('victory camera fits the line and final chip drop at every aspect', () {
    final List<List<BoardPosition>> lines = <List<BoardPosition>>[
      const [
        BoardPosition(0, 0, 0),
        BoardPosition(1, 1, 1),
        BoardPosition(2, 2, 2),
        BoardPosition(3, 3, 3),
      ],
      const [
        BoardPosition(3, 0, 0),
        BoardPosition(2, 1, 1),
        BoardPosition(1, 2, 2),
        BoardPosition(0, 3, 3),
      ],
    ];
    for (final Size viewport in const <Size>[
      Size(280, 800),
      Size(390, 650),
      Size(800, 390),
    ]) {
      final VictoryCameraShot shot = fitVictoryCamera(
        lines: lines,
        last: lines.first.last,
        currentTarget: vm.Vector3(0, .25, 0),
        currentAzimuth: -.7,
        currentPolar: .65,
        currentDistance: 7,
        fovRadians: 35 * math.pi / 180,
        viewport: viewport,
      );
      final double horizontal = math.cos(shot.toPolar) * shot.toDistance;
      final vm.Vector3 position =
          shot.toTarget +
          vm.Vector3(-math.sin(shot.toAzimuth), 0, -math.cos(shot.toAzimuth)) *
              horizontal +
          vm.Vector3(0, math.sin(shot.toPolar) * shot.toDistance, 0);
      final fs.PerspectiveCamera camera = fs.PerspectiveCamera(
        fovRadiansY: shot.fovRadians,
        position: position,
        target: shot.toTarget,
        up: vm.Vector3(0, 1, 0),
        fovFar: 100,
      );
      final List<vm.Vector3> points = lines
          .expand((line) => line)
          .map(GameSceneController.position)
          .toList();
      points.add(GameSceneController.position(lines.first.last)..y += 2.2);
      for (final vm.Vector3 point in points) {
        for (final double x in const [-.42, .42]) {
          for (final double y in const [-.3, .3]) {
            for (final double z in const [-.42, .42]) {
              final Offset screen = camera.worldToScreen(
                point + vm.Vector3(x, y, z),
                viewport,
              )!;
              expect(
                screen.dx,
                inInclusiveRange(viewport.width * .1, viewport.width * .9),
              );
              expect(
                screen.dy,
                inInclusiveRange(viewport.height * .1, viewport.height * .9),
              );
            }
          }
        }
      }
    }
  });

  test('victory FOV preserves pixel scale after an inline result resize', () {
    const Size viewport = Size(390, 650);
    final VictoryCameraShot shot = fitVictoryCamera(
      lines: const [
        [
          BoardPosition(0, 0, 0),
          BoardPosition(1, 0, 0),
          BoardPosition(2, 0, 0),
          BoardPosition(3, 0, 0),
        ],
      ],
      last: const BoardPosition(3, 0, 0),
      currentTarget: vm.Vector3(0, .25, 0),
      currentAzimuth: 0,
      currentPolar: .65,
      currentDistance: 15,
      fovRadians: 35 * math.pi / 180,
      viewport: viewport,
    );
    final double resizedFov = victoryFov(viewportHeight: 430, shot: shot);
    final double before = viewport.height / (2 * math.tan(shot.fovRadians / 2));
    final double after = 430 / (2 * math.tan(resizedFov / 2));

    expect(after, closeTo(before, 1e-9));
  });
}
