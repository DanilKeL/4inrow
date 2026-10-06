import 'dart:math' as math;
import 'dart:ui' show FrameTiming, Size;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/scene/game_camera_orbit.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:vector_math/vector_math.dart' as vm;

class GameSceneView extends StatefulWidget {
  const new({
    required this.data,
    required this.settings,
    required this.onPlace,
    this.demo = false,
    super.key,
  });

  final GameViewData data;
  final AppSettings settings;
  final void Function(int x, int y) onPlace;
  final bool demo;

  @override
  State<GameSceneView> createState() => _GameSceneViewState();
}

class _GameSceneViewState extends State<GameSceneView> {
  late final GameSceneController _controller = GameSceneController();
  bool _ready = false;
  Object? _error;
  double _azimuth = 0;
  double _polar = .65;
  double _distance = 15;
  double _startDistance = 15;
  double _azimuthVelocity = 0;
  double _polarVelocity = 0;
  double? _goalAzimuth;
  double? _goalPolar;
  double? _goalDistance;
  bool _cameraInitialized = false;
  bool _rotating = false;
  vm.Vector3 _target = vm.Vector3(0, .25, 0);
  vm.Vector3 _targetGoal = vm.Vector3(0, .25, 0);
  int _cameraReset = -1;
  Size _size = Size.zero;
  double _renderScale = 1;
  final List<double> _frameTimes = [];
  final ValueNotifier<int> _sceneRepaint = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      _sync();
      if (mounted) setState(() => _ready = true);
    } on Exception catch (error, stackTrace) {
      debugPrint('FOUR³ scene initialization failed: $error\n$stackTrace');
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didUpdateWidget(covariant GameSceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    if (!widget.settings.hints || !widget.data.canPlace) {
      _controller.hideGhost();
    }
  }

  void _sync() {
    if (!_controller.ready) return;
    _controller.sync(
      snapshot: widget.data.displayedSnapshot,
      xray: widget.data.xray,
      layers: widget.data.layers,
      animations: widget.settings.animations,
      introduction: widget.demo,
    );
    final bool viewChanged = oldViewNeedsReset(widget.data.cameraView);
    if (_cameraReset != widget.data.cameraReset || viewChanged) {
      _cameraReset = widget.data.cameraReset;
      _resetCamera(widget.data.cameraView);
    }
    if (widget.data.snapshot.status == GameStatus.won) {
      _targetGoal = _controller.winningTarget();
    }
  }

  CameraView? _lastView;
  bool oldViewNeedsReset(CameraView view) {
    if (_lastView == view) return false;
    _lastView = view;
    return true;
  }

  void _resetCamera(CameraView view) {
    final double aspect = _size.isEmpty ? 1.0 : _size.width / _size.height;
    final double fit = math.max(1, .9 / aspect);
    final vm.Vector3 raw = switch (view) {
      CameraView.top => vm.Vector3(0, 13.7, .035),
      CameraView.front => vm.Vector3(0, 5.6, 12.8),
      CameraView.perspective =>
        widget.demo ? vm.Vector3(8.7, 7.25, 9.8) : vm.Vector3(7.4, 9.2, 9.3),
    }..scale(fit * (widget.demo ? .92 : 1));
    _targetGoal = vm.Vector3(0, .25, 0);
    final vm.Vector3 offset = raw - _targetGoal;
    final double distance = offset.length.clamp(7, 23);
    final double azimuth = math.atan2(-offset.x, -offset.z);
    final double polar = math.asin((offset.y / distance).clamp(-1, 1));
    _azimuthVelocity = 0;
    _polarVelocity = 0;
    if (!_cameraInitialized || !widget.settings.animations) {
      _azimuth = azimuth;
      _polar = polar;
      _distance = distance;
      _target = _targetGoal.clone();
      _clearCameraGoal();
    } else {
      _goalAzimuth = azimuth;
      _goalPolar = polar;
      _goalDistance = distance;
    }
    _cameraInitialized = true;
  }

  void _clearCameraGoal() {
    _goalAzimuth = null;
    _goalPolar = null;
    _goalDistance = null;
  }

  fs.PerspectiveCamera _camera() {
    final double horizontal = math.cos(_polar) * _distance;
    final vm.Vector3 position =
        _target +
        vm.Vector3(-math.sin(_azimuth), 0, -math.cos(_azimuth)) * horizontal +
        vm.Vector3(0, math.sin(_polar) * _distance, 0);
    return fs.PerspectiveCamera(
      fovRadiansY: 35 * math.pi / 180,
      position: position,
      target: _target,
      up: vm.Vector3(0, 1, 0),
      fovFar: 100,
    );
  }

  void _tick(Duration elapsed, double delta) {
    final double seconds =
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _controller.setClock(seconds);
    _controller.tick(seconds, delta);
    final double response = widget.settings.animations
        ? 1 - math.exp(-delta * 6)
        : 1.0;
    _target += (_targetGoal - _target) * response;
    if (_goalAzimuth case final goalAzimuth?) {
      final double goalPolar = _goalPolar!;
      final double goalDistance = _goalDistance!;
      _azimuth += _shortestAngle(_azimuth, goalAzimuth) * response;
      _polar += (goalPolar - _polar) * response;
      _distance += (goalDistance - _distance) * response;
      if (_shortestAngle(_azimuth, goalAzimuth).abs() < .0005 &&
          (_polar - goalPolar).abs() < .0005 &&
          (_distance - goalDistance).abs() < .005) {
        _azimuth = goalAzimuth;
        _polar = goalPolar;
        _distance = goalDistance;
        _clearCameraGoal();
      }
    } else if (_azimuthVelocity != 0 || _polarVelocity != 0) {
      final GameCameraMotion motion =
          GameCameraOrbit(azimuth: _azimuth, polar: _polar).applyInertia(
            azimuthVelocity: _azimuthVelocity,
            polarVelocity: _polarVelocity,
            deltaSeconds: delta,
          );
      _azimuth = motion.orbit.azimuth;
      _polar = motion.orbit.polar;
      _azimuthVelocity = motion.settled ? 0 : motion.azimuthVelocity;
      _polarVelocity = motion.settled ? 0 : motion.polarVelocity;
    }
    _sceneRepaint.value++;
  }

  static double _shortestAngle(double from, double to) =>
      (to - from + math.pi) % (2 * math.pi) - math.pi;

  void _onTapUp(TapUpDetails details) {
    if (!widget.data.canPlace || !_ready || _size.isEmpty) return;
    final vm.Ray ray = _camera().screenPointToRay(details.localPosition, _size);
    final ({int x, int y})? column = _controller.pick(ray);
    _controller.hideGhost();
    if (column != null) widget.onPlace(column.x, column.y);
  }

  void _onHover(PointerHoverEvent event) {
    if (!widget.settings.hints || !widget.data.canPlace || !_ready) {
      _controller.hideGhost();
      return;
    }
    final vm.Ray ray = _camera().screenPointToRay(event.localPosition, _size);
    final ({int x, int y})? column = _controller.pick(ray);
    if (column == null) {
      _controller.hideGhost();
    } else {
      _controller.showGhost(column.x, column.y);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _controller.hideGhost();
    _startDistance = _distance;
    _azimuthVelocity = 0;
    _polarVelocity = 0;
    _clearCameraGoal();
    _targetGoal = _target.clone();
    _rotating = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      _distance = (_startDistance / details.scale).clamp(7, 23);
      _rotating = false;
    } else if (_size.height > 0) {
      _rotating = true;
      final GameCameraOrbit orbit =
          GameCameraOrbit(azimuth: _azimuth, polar: _polar).applyDrag(
            deltaX: details.focalPointDelta.dx,
            deltaY: details.focalPointDelta.dy,
            viewportHeight: _size.height,
          );
      _azimuth = orbit.azimuth;
      _polar = orbit.polar;
    }
    _targetGoal = _target.clone();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_rotating || _size.height <= 0) return;
    final ({double azimuth, double polar}) velocity =
        GameCameraOrbit.velocityFromPixels(
          pixelsPerSecondX: details.velocity.pixelsPerSecond.dx,
          pixelsPerSecondY: details.velocity.pixelsPerSecond.dy,
          viewportHeight: _size.height,
        );
    _azimuthVelocity = velocity.azimuth;
    _polarVelocity = velocity.polar;
    _rotating = false;
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_ready) return;
    _frameTimes.addAll(
      timings.map((timing) => timing.totalSpan.inMicroseconds / 1000),
    );
    if (_frameTimes.length < 120) return;
    _frameTimes.sort();
    final double p95 =
        _frameTimes[(_frameTimes.length * .95).floor().clamp(
          0,
          _frameTimes.length - 1,
        )];
    _frameTimes.clear();
    double next = _renderScale;
    if (p95 > 18.5) next = math.max(.75, next - .05);
    if (p95 < 14.5) next = math.min(1, next + .05);
    if (next != _renderScale) {
      _renderScale = next;
      _controller.scene.renderScale = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: const Color(0xFFE8E5DF),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              context.l10n.sceneLoadFailed,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFFE8E5DF),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size nextSize = constraints.biggest;
        if (_size != nextSize) {
          _size = nextSize;
          _resetCamera(widget.data.cameraView);
        }
        final double dpr = MediaQuery.devicePixelRatioOf(context);
        final double area = math.max(1, _size.width * _size.height * dpr * dpr);
        final double budgetScale = math.sqrt(3000000 / area).clamp(.75, 1.0);
        if (_renderScale > budgetScale) {
          _renderScale = budgetScale;
          _controller.scene.renderScale = budgetScale;
        }
        return MouseRegion(
          onHover: _onHover,
          onExit: (_) => _controller.hideGhost(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                fs.SceneView(
                  _controller.scene,
                  cameraBuilder: (_) => _camera(),
                  onTick: _tick,
                  pixelRatio: dpr,
                  loadingBuilder: (_, progress) => Center(
                    child: CircularProgressIndicator(
                      value: progress == 0 ? null : progress,
                    ),
                  ),
                ),
                if (widget.data.displayedSnapshot.winningLines.isNotEmpty)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _WinningLinesPainter(
                        snapshot: widget.data.displayedSnapshot,
                        layers: widget.data.layers,
                        camera: _camera,
                        devicePixelRatio: dpr,
                        repaint: _sceneRepaint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _sceneRepaint.dispose();
    _controller.dispose();
    super.dispose();
  }
}

final class _WinningLinesPainter extends CustomPainter {
  new({
    required this.snapshot,
    required this.layers,
    required this.camera,
    required this.devicePixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GameSnapshot snapshot;
  final List<int> layers;
  final fs.PerspectiveCamera Function() camera;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final fs.PerspectiveCamera activeCamera = camera();
    final Paint paint = Paint()
      ..color = const Color(0xFF2955E7).withValues(alpha: .83)
      ..strokeWidth = 4 / devicePixelRatio
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final List<BoardPosition> line in snapshot.winningLines) {
      for (var index = 1; index < line.length; index++) {
        final BoardPosition first = line[index - 1];
        final BoardPosition second = line[index];
        if (!layers.contains(first.z) || !layers.contains(second.z)) continue;
        final vm.Vector3 firstWorld = GameSceneController.position(first)
          ..y += .27;
        final vm.Vector3 secondWorld = GameSceneController.position(second)
          ..y += .27;
        final Offset? a = activeCamera.worldToScreen(firstWorld, size);
        final Offset? b = activeCamera.worldToScreen(secondWorld, size);
        if (a != null && b != null) canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WinningLinesPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.layers != layers ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
