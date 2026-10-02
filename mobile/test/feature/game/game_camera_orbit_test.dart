import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/scene/game_camera_orbit.dart';

void main() {
  group('camera orbit drag', () {
    const double azimuth = .4;
    const double polar = .5;
    const double viewportHeight = 200;
    const double drag = 20;
    const double expectedDelta =
        2 * math.pi * GameCameraOrbit.rotateSpeed * drag / viewportHeight;

    test('applies the expected sensitivity and horizontal direction', () {
      final GameCameraOrbit right = const GameCameraOrbit(
        azimuth: azimuth,
        polar: polar,
      ).applyDrag(deltaX: drag, deltaY: 0, viewportHeight: viewportHeight);
      final GameCameraOrbit left = const GameCameraOrbit(
        azimuth: azimuth,
        polar: polar,
      ).applyDrag(deltaX: -drag, deltaY: 0, viewportHeight: viewportHeight);

      expect(right.azimuth, closeTo(azimuth + expectedDelta, 1e-12));
      expect(left.azimuth, closeTo(azimuth - expectedDelta, 1e-12));
      expect(right.polar, polar);
      expect(left.polar, polar);
    });

    test('matches web vertical direction', () {
      final GameCameraOrbit down = const GameCameraOrbit(
        azimuth: azimuth,
        polar: polar,
      ).applyDrag(deltaX: 0, deltaY: drag, viewportHeight: viewportHeight);
      final GameCameraOrbit up = const GameCameraOrbit(
        azimuth: azimuth,
        polar: polar,
      ).applyDrag(deltaX: 0, deltaY: -drag, viewportHeight: viewportHeight);

      expect(down.polar, closeTo(polar + expectedDelta, 1e-12));
      expect(up.polar, closeTo(polar - expectedDelta, 1e-12));
      expect(down.azimuth, azimuth);
      expect(up.azimuth, azimuth);
    });

    test('clamps vertical orbit to the camera limits', () {
      final GameCameraOrbit down = const GameCameraOrbit(
        azimuth: azimuth,
        polar: polar,
      ).applyDrag(deltaX: 0, deltaY: 1000, viewportHeight: viewportHeight);
      final GameCameraOrbit up = const GameCameraOrbit(
        azimuth: azimuth,
        polar: polar,
      ).applyDrag(deltaX: 0, deltaY: -1000, viewportHeight: viewportHeight);

      expect(down.polar, GameCameraOrbit.maxPolar);
      expect(up.polar, GameCameraOrbit.minPolar);
    });

    test('converts release velocity with the same drag scale', () {
      final ({double azimuth, double polar}) velocity =
          GameCameraOrbit.velocityFromPixels(
            pixelsPerSecondX: 100,
            pixelsPerSecondY: -50,
            viewportHeight: viewportHeight,
          );

      expect(velocity.azimuth, closeTo(expectedDelta * 5, 1e-12));
      expect(velocity.polar, closeTo(-expectedDelta * 2.5, 1e-12));
    });

    test('inertia decay is frame-rate independent', () {
      GameCameraMotion at60 = const GameCameraMotion(
        orbit: GameCameraOrbit(azimuth: azimuth, polar: polar),
        azimuthVelocity: 2,
        polarVelocity: .2,
      );
      GameCameraMotion at120 = at60;
      for (var frame = 0; frame < 60; frame++) {
        at60 = at60.orbit.applyInertia(
          azimuthVelocity: at60.azimuthVelocity,
          polarVelocity: at60.polarVelocity,
          deltaSeconds: 1 / 60,
        );
      }
      for (var frame = 0; frame < 120; frame++) {
        at120 = at120.orbit.applyInertia(
          azimuthVelocity: at120.azimuthVelocity,
          polarVelocity: at120.polarVelocity,
          deltaSeconds: 1 / 120,
        );
      }

      expect(at60.orbit.azimuth, closeTo(at120.orbit.azimuth, 1e-10));
      expect(at60.orbit.polar, closeTo(at120.orbit.polar, 1e-10));
      expect(at60.azimuthVelocity, closeTo(at120.azimuthVelocity, 1e-10));
    });

    test('inertia stops vertical velocity at a polar limit', () {
      final GameCameraMotion result =
          const GameCameraOrbit(
            azimuth: azimuth,
            polar: GameCameraOrbit.maxPolar - .001,
          ).applyInertia(
            azimuthVelocity: 0,
            polarVelocity: 20,
            deltaSeconds: 1 / 60,
          );

      expect(result.orbit.polar, GameCameraOrbit.maxPolar);
      expect(result.polarVelocity, 0);
    });
  });
}
