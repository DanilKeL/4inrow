import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';
import 'package:vector_math/vector_math.dart' as vm;

final class VictoryCameraShot {
  new({
    required this.fromTarget,
    required this.toTarget,
    required this.fromAzimuth,
    required this.toAzimuth,
    required this.fromPolar,
    required this.toPolar,
    required this.fromDistance,
    required this.toDistance,
    required this.viewportHeight,
    required this.fovRadians,
  });

  final vm.Vector3 fromTarget;
  final vm.Vector3 toTarget;
  final double fromAzimuth;
  final double toAzimuth;
  final double fromPolar;
  final double toPolar;
  final double fromDistance;
  final double toDistance;
  final double viewportHeight;
  final double fovRadians;
  bool released = false;
}

double shortestVictoryAngle(double from, double to) =>
    (to - from + math.pi) % (2 * math.pi) - math.pi;

VictoryCameraShot fitVictoryCamera({
  required List<List<BoardPosition>> lines,
  required BoardPosition last,
  required vm.Vector3 currentTarget,
  required double currentAzimuth,
  required double currentPolar,
  required double currentDistance,
  required double fovRadians,
  required Size viewport,
}) {
  final List<vm.Vector3> points = lines
      .expand((line) => line)
      .map(GameSceneController.position)
      .toList(growable: false);
  final vm.Vector3 target = vm.Vector3.zero();
  for (final vm.Vector3 point in points) {
    target.add(point);
  }
  target.scale(1 / points.length);

  final vm.Vector3 first = GameSceneController.position(lines.first.first);
  final vm.Vector3 end = GameSceneController.position(lines.first.last);
  final vm.Vector3 direction = end - first;
  final double fromTheta = currentAzimuth + math.pi;
  final double normal = math.atan2(-direction.z, direction.x);
  final List<double> turns = <double>[
    shortestVictoryAngle(fromTheta, normal),
    shortestVictoryAngle(fromTheta, normal + math.pi),
  ]..sort((a, b) => a.abs().compareTo(b.abs()));
  final double turn =
      math.sqrt(direction.x * direction.x + direction.z * direction.z) < .01
      ? .28
      : turns.first;
  final double toAzimuth = fromTheta + turn - math.pi;
  const double toPolar = math.pi / 2 - .82;
  final double aspect = viewport.height <= 0
      ? 1
      : viewport.width / viewport.height;
  final double fit = math.max(1, .9 / aspect);
  double radius = math.max(7, math.min(currentDistance * .9, 10.5 * fit));

  final double horizontalRadius = math.cos(toPolar);
  final vm.Vector3 backward = vm.Vector3(
    -math.sin(toAzimuth) * horizontalRadius,
    math.sin(toPolar),
    -math.cos(toAzimuth) * horizontalRadius,
  );
  final vm.Vector3 right = vm.Vector3(0, 1, 0)..cross(backward);
  right.normalize();
  final vm.Vector3 up = backward.clone()..cross(right);
  final double vertical = math.tan(fovRadians / 2) * .8;
  final double horizontal = vertical * aspect;
  final vm.Vector3 drop = GameSceneController.position(last)..y += 2.2;
  for (final vm.Vector3 point in <vm.Vector3>[...points, drop]) {
    for (final double x in const [-.42, .42]) {
      for (final double y in const [-.3, .3]) {
        for (final double z in const [-.42, .42]) {
          final vm.Vector3 offset = point + vm.Vector3(x, y, z) - target;
          final double depth = offset.dot(backward);
          radius = math.max(
            radius,
            math.max(
              depth + offset.dot(right).abs() / horizontal,
              math.max(depth + offset.dot(up).abs() / vertical, depth + .1),
            ),
          );
        }
      }
    }
  }
  return VictoryCameraShot(
    fromTarget: currentTarget.clone(),
    toTarget: target,
    fromAzimuth: currentAzimuth,
    toAzimuth: toAzimuth,
    fromPolar: currentPolar,
    toPolar: toPolar,
    fromDistance: currentDistance,
    toDistance: radius,
    viewportHeight: viewport.height,
    fovRadians: fovRadians,
  );
}

double victoryFov({
  required double viewportHeight,
  required VictoryCameraShot shot,
}) {
  if (viewportHeight <= 0 || shot.viewportHeight <= 0) {
    return shot.fovRadians;
  }
  return 2 *
      math.atan(
        math.tan(shot.fovRadians / 2) * viewportHeight / shot.viewportHeight,
      );
}
