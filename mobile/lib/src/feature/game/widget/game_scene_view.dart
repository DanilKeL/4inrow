import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming, Size;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/appearance/data/skin_image_cache.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';
import 'package:four3/src/feature/components/progress/app_circular_progress_indicator.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/scene/game_camera_orbit.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';
import 'package:four3/src/feature/game/scene/victory_camera.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/service/victory_presentation.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:vector_math/vector_math.dart' as vm;

typedef GameCameraFraming = ({vm.Vector3 position, vm.Vector3 target});

@visibleForTesting
GameCameraFraming gameCameraResetFraming({
  required CameraView view,
  required Size viewport,
  required bool demo,
  double inset = 8,
}) {
  // Keep the active board at the same apparent size it had before the old
  // 16 px canvas gutters were removed. The recovered width becomes breathing
  // room around the projection instead of zooming the camera back in.
  final double framingWidth = demo
      ? viewport.width
      : math.max(1, viewport.width - 32);
  final double aspect = viewport.isEmpty ? 1 : framingWidth / viewport.height;
  final double fit = math.max(1, .9 / aspect);
  final vm.Vector3 target = vm.Vector3(0, demo ? -.35 : -.15, 0);
  final vm.Vector3 base = switch (view) {
    CameraView.top => vm.Vector3(0, 13.7, .035),
    CameraView.front => vm.Vector3(0, 5.6, 12.8),
    CameraView.perspective =>
      demo ? vm.Vector3(8.7, 7.25, 9.8) : vm.Vector3(7.4, 9.2, 9.3),
  };
  final double nominalScale = demo ? .88 : .84;
  double framingScale = 1;
  if (!demo && !viewport.isEmpty) {
    for (var step = 0; step <= 12; step++) {
      final double candidate = 1 + step * .0025;
      final vm.Vector3 position = base.clone()
        ..scale(fit * nominalScale * candidate);
      if (_boardFitsViewport(position, target, viewport, inset)) {
        framingScale = candidate;
        break;
      }
      framingScale = 1.03;
    }
  }
  return (
    position: base.clone()..scale(fit * nominalScale * framingScale),
    target: target,
  );
}

bool _boardFitsViewport(
  vm.Vector3 position,
  vm.Vector3 target,
  Size viewport,
  double inset,
) {
  final fs.PerspectiveCamera camera = fs.PerspectiveCamera(
    fovRadiansY: 35 * math.pi / 180,
    position: position,
    target: target,
    up: vm.Vector3(0, 1, 0),
    fovFar: 100,
  );
  for (final vm.Vector3 worldPoint in gameBoardFramingEnvelope()) {
    final Offset? point = camera.worldToScreen(worldPoint, viewport);
    if (point == null ||
        point.dx < inset ||
        point.dx > viewport.width - inset ||
        point.dy < inset ||
        point.dy > viewport.height - inset) {
      return false;
    }
  }
  return true;
}

@visibleForTesting
List<vm.Vector3> gameBoardFramingEnvelope() => <vm.Vector3>[
  for (final double x in const <double>[-2.28, 2.28])
    for (final double y in const <double>[-.43, .18])
      for (final double z in const <double>[-2.28, 2.28]) vm.Vector3(x, y, z),
  for (final double x in const <double>[-2.28, 2.28])
    for (final double y in const <double>[.13, 2.9])
      for (final double z in const <double>[-2.28, 2.28]) vm.Vector3(x, y, z),
];

class GameSceneView extends StatefulWidget {
  const new({
    required this.data,
    required this.settings,
    required this.skin,
    required this.imageCache,
    required this.onPlace,
    this.victory,
    this.demo = false,
    super.key,
  });

  final GameViewData data;
  final AppSettings settings;
  final Skin skin;
  final SkinImageCache imageCache;
  final void Function(int x, int y) onPlace;
  final VictoryPresentationSession? victory;
  final bool demo;

  @override
  State<GameSceneView> createState() => _GameSceneViewState();
}

class _GameSceneViewState extends State<GameSceneView> {
  late final GameSceneController _controller;
  bool _ready = false;
  Object? _error;
  double _azimuth = 0;
  double _polar = .65;
  double _distance = 15;
  double _startDistance = 15;
  double _minimumDistance = 7;
  double _maximumDistance = 23;
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
  Timer? _invalidColumnTimer;
  VictoryCameraShot? _victoryShot;
  String? _victoryKey;

  @override
  void initState() {
    super.initState();
    _controller = GameSceneController(imageCache: widget.imageCache);
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize(widget.skin);
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
    if (oldWidget.skin != widget.skin) {
      unawaited(_controller.applySkin(widget.skin));
    }
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
      animations:
          widget.settings.animations &&
          !MediaQuery.disableAnimationsOf(context),
      introduction: widget.demo,
      victoryAnimated: widget.victory?.animations ?? false,
    );
    final bool viewChanged = oldViewNeedsReset(widget.data.cameraView);
    if (_cameraReset != widget.data.cameraReset || viewChanged) {
      _cameraReset = widget.data.cameraReset;
      _resetCamera(widget.data.cameraView);
    }
    _syncVictoryCamera();
  }

  void _syncVictoryCamera() {
    final VictoryPresentationSession? victory = widget.victory;
    if (victory == null || !victory.animations) {
      _victoryKey = null;
      _victoryShot = null;
      _minimumDistance = 7;
      _maximumDistance = 23;
      return;
    }
    if (_victoryKey == victory.key ||
        _size.isEmpty ||
        victory.elapsed >= victoryCinematicDuration ||
        widget.data.snapshot.history.isEmpty ||
        widget.data.snapshot.winningLines.isEmpty) {
      return;
    }
    _victoryKey = victory.key;
    _azimuthVelocity = 0;
    _polarVelocity = 0;
    _clearCameraGoal();
    _targetGoal = _target.clone();
    _victoryShot = fitVictoryCamera(
      lines: widget.data.snapshot.winningLines,
      last: widget.data.snapshot.history.last.position,
      currentTarget: _target,
      currentAzimuth: _azimuth,
      currentPolar: _polar,
      currentDistance: _distance,
      fovRadians: 35 * math.pi / 180,
      viewport: _size,
    );
  }

  CameraView? _lastView;
  bool oldViewNeedsReset(CameraView view) {
    if (_lastView == view) return false;
    _lastView = view;
    return true;
  }

  void _resetCamera(CameraView view) {
    final GameCameraFraming framing = gameCameraResetFraming(
      view: view,
      viewport: _size,
      demo: widget.demo,
    );
    final vm.Vector3 raw = framing.position;
    _targetGoal = framing.target;
    final vm.Vector3 offset = raw - _targetGoal;
    final double distance = offset.length.clamp(7, 23);
    _minimumDistance = distance;
    _maximumDistance = 23;
    final double azimuth = math.atan2(-offset.x, -offset.z);
    final double polar = math.asin((offset.y / distance).clamp(-1, 1));
    _azimuthVelocity = 0;
    _polarVelocity = 0;
    if (!_cameraInitialized ||
        !widget.settings.animations ||
        MediaQuery.disableAnimationsOf(context)) {
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
      fovRadiansY: _victoryShot == null
          ? 35 * math.pi / 180
          : victoryFov(viewportHeight: _size.height, shot: _victoryShot!),
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
    final VictoryPresentationSession? victory = widget.victory;
    final VictoryProgress? presentation = victory != null && victory.animations
        ? victoryProgress(victory.elapsed)
        : null;
    _controller.tick(seconds, delta, victory: presentation);
    final VictoryCameraShot? shot = _victoryShot;
    if (victory != null && shot != null && _victoryKey == victory.key) {
      if (victory.cameraLocked) {
        final double raw =
            victory.elapsed.inMicroseconds / winCameraDuration.inMicroseconds;
        final double eased = victorySmoothStep(raw);
        _azimuth =
            shot.fromAzimuth +
            shortestVictoryAngle(shot.fromAzimuth, shot.toAzimuth) * eased;
        _polar = shot.fromPolar + (shot.toPolar - shot.fromPolar) * eased;
        _distance =
            shot.fromDistance + (shot.toDistance - shot.fromDistance) * eased;
        _target = shot.fromTarget.clone()
          ..add((shot.toTarget - shot.fromTarget) * eased);
        _targetGoal = _target.clone();
        _sceneRepaint.value++;
        return;
      }
      if (!shot.released) {
        _minimumDistance = math.min(7, _distance);
        _maximumDistance = math.max(23, _distance);
        shot.released = true;
        _clearCameraGoal();
      }
    }
    final double response =
        widget.settings.animations && !MediaQuery.disableAnimationsOf(context)
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
    if (column == null) return;
    final int columnIndex = column.y * GameEngine.size + column.x;
    if (widget.data.snapshot.heights[columnIndex] >= GameEngine.size) {
      _controller.showInvalidColumn(column.x, column.y);
      _invalidColumnTimer?.cancel();
      _invalidColumnTimer = Timer(const Duration(milliseconds: 650), () {
        _controller.hideInvalidColumn();
      });
    }
    widget.onPlace(column.x, column.y);
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
    if (widget.victory?.cameraLocked ?? false) return;
    _controller.hideGhost();
    _startDistance = _distance;
    _azimuthVelocity = 0;
    _polarVelocity = 0;
    _clearCameraGoal();
    _targetGoal = _target.clone();
    _rotating = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (widget.victory?.cameraLocked ?? false) return;
    if (details.pointerCount > 1) {
      _distance = (_startDistance / details.scale).clamp(
        _minimumDistance,
        _maximumDistance,
      );
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
    if (widget.victory?.cameraLocked ?? false) return;
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
        color: _skinColor(widget.skin.palette.room),
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
      return ColoredBox(
        color: _skinColor(widget.skin.palette.room),
        child: const Center(child: AppCircularProgressIndicator()),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size nextSize = constraints.biggest;
        if (_size != nextSize) {
          _size = nextSize;
          if (_victoryShot == null) _resetCamera(widget.data.cameraView);
          _syncVictoryCamera();
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
                    child: AppCircularProgressIndicator(
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
                        color: _skinColor(widget.skin.palette.accent),
                        camera: _camera,
                        victory: widget.victory,
                        devicePixelRatio: dpr,
                        repaint: _sceneRepaint,
                      ),
                    ),
                  ),
                if (MediaQuery.accessibleNavigationOf(context))
                  GameAccessibleBoardGrid(
                    data: widget.data,
                    onPlace: widget.onPlace,
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
    _invalidColumnTimer?.cancel();
    _controller.hideInvalidColumn();
    _sceneRepaint.dispose();
    _controller.dispose();
    super.dispose();
  }
}

class GameAccessibleBoardGrid extends StatelessWidget {
  const new({required this.data, required this.onPlace, super.key});

  final GameViewData data;
  final void Function(int x, int y) onPlace;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.transparent,
    child: Column(
      children: [
        for (var y = 0; y < GameEngine.size; y++)
          Expanded(
            child: Row(
              children: [
                for (var x = 0; x < GameEngine.size; x++)
                  Expanded(
                    child: _AccessibleColumn(
                      data: data,
                      x: x,
                      y: y,
                      onPlace: onPlace,
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _AccessibleColumn extends StatelessWidget {
  const new({
    required this.data,
    required this.x,
    required this.y,
    required this.onPlace,
  });

  final GameViewData data;
  final int x;
  final int y;
  final void Function(int x, int y) onPlace;

  @override
  Widget build(BuildContext context) {
    final int height = data.snapshot.heights[y * GameEngine.size + x];
    final bool enabled = data.canPlace && height < GameEngine.size;
    return Semantics(
      key: ValueKey<String>('board-column-$x-$y'),
      button: true,
      enabled: enabled,
      label: context.l10n.boardColumn(x + 1, y + 1, height),
      onTap: enabled ? () => onPlace(x, y) : null,
      child: const SizedBox.expand(),
    );
  }
}

Color _skinColor(String value) =>
    Color(int.parse('ff${value.substring(1)}', radix: 16));

final class _WinningLinesPainter extends CustomPainter {
  new({
    required this.snapshot,
    required this.layers,
    required this.color,
    required this.camera,
    required this.devicePixelRatio,
    required this.victory,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GameSnapshot snapshot;
  final List<int> layers;
  final Color color;
  final fs.PerspectiveCamera Function() camera;
  final double devicePixelRatio;
  final VictoryPresentationSession? victory;

  @override
  void paint(Canvas canvas, Size size) {
    final fs.PerspectiveCamera activeCamera = camera();
    final Paint paint = Paint()
      ..color = color.withValues(alpha: .83)
      ..strokeWidth = 4 / devicePixelRatio
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final VictoryProgress? presentation = victory != null && victory!.animations
        ? victoryProgress(victory!.elapsed)
        : null;
    final BoardPosition? last = snapshot.history.isEmpty
        ? null
        : snapshot.history.last.position;
    for (final List<BoardPosition> source in snapshot.winningLines) {
      final List<BoardPosition> line =
          presentation != null &&
              last != null &&
              source.isNotEmpty &&
              source.last == last
          ? source.reversed.toList(growable: false)
          : source;
      final int total = math.max(0, line.length - 1);
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
        final double progress = presentation == null
            ? 1
            : victorySegmentProgress(
                presentation.lineProgress,
                index - 1,
                total,
              );
        if (a != null && b != null && progress > 0) {
          paint.color = color.withValues(
            alpha: .83 * math.min(1, progress * 4),
          );
          canvas.drawLine(a, Offset.lerp(a, b, progress)!, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WinningLinesPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.layers != layers ||
      oldDelegate.color != color ||
      oldDelegate.victory?.key != victory?.key ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
