import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
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
}
