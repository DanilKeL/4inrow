import 'dart:math' as math;

final class GameCameraOrbit {
  const new({required this.azimuth, required this.polar});

  static const double rotateSpeed = .65;
  static const double dampingFactor = .09;
  static const double referenceFps = 60;
  static const double minPolar = .001;
  static const double maxPolar = math.pi / 2.16;
  static const double radiansPerViewport = 2 * math.pi * rotateSpeed;

  final double azimuth;
  final double polar;

  GameCameraOrbit applyDrag({
    required double deltaX,
    required double deltaY,
    required double viewportHeight,
  }) {
    if (viewportHeight <= 0) return this;
    final double scale = radiansPerViewport / viewportHeight;
    return GameCameraOrbit(
      azimuth: azimuth + deltaX * scale,
      polar: (polar + deltaY * scale).clamp(minPolar, maxPolar),
    );
  }

  static ({double azimuth, double polar}) velocityFromPixels({
    required double pixelsPerSecondX,
    required double pixelsPerSecondY,
    required double viewportHeight,
  }) {
    if (viewportHeight <= 0) return (azimuth: 0, polar: 0);
    final double scale = radiansPerViewport / viewportHeight;
    return (azimuth: pixelsPerSecondX * scale, polar: pixelsPerSecondY * scale);
  }

  GameCameraMotion applyInertia({
    required double azimuthVelocity,
    required double polarVelocity,
    required double deltaSeconds,
  }) {
    if (deltaSeconds <= 0) {
      return GameCameraMotion(
        orbit: this,
        azimuthVelocity: azimuthVelocity,
        polarVelocity: polarVelocity,
      );
    }
    final double decay = math
        .pow(1 - dampingFactor, deltaSeconds * referenceFps)
        .toDouble();
    final double decayRate = -math.log(1 - dampingFactor) * referenceFps;
    final double travel = (1 - decay) / decayRate;
    final double nextAzimuth = azimuth + azimuthVelocity * travel;
    final double unclampedPolar = polar + polarVelocity * travel;
    final double nextPolar = unclampedPolar.clamp(minPolar, maxPolar);
    return GameCameraMotion(
      orbit: GameCameraOrbit(azimuth: nextAzimuth, polar: nextPolar),
      azimuthVelocity: azimuthVelocity * decay,
      polarVelocity: nextPolar == unclampedPolar ? polarVelocity * decay : 0,
    );
  }
}

final class GameCameraMotion {
  const new({
    required this.orbit,
    required this.azimuthVelocity,
    required this.polarVelocity,
  });

  final GameCameraOrbit orbit;
  final double azimuthVelocity;
  final double polarVelocity;

  bool get settled =>
      azimuthVelocity.abs() < .0001 && polarVelocity.abs() < .0001;
}
