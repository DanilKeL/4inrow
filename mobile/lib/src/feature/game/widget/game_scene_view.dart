import 'dart:math' as math;
import 'dart:ui' show FrameTiming, Size;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:four3/src/feature/game/bloc/game_bloc.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';
import 'package:four3/src/feature/settings/model/app_settings.dart';
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
  vm.Vector3 _target = vm.Vector3(0, .25, 0);
  vm.Vector3 _targetGoal = vm.Vector3(0, .25, 0);
  int _cameraReset = -1;
  Size _size = Size.zero;
  double _renderScale = 1;
  final List<double> _frameTimes = [];

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
  }

  void _sync() {
    if (!_controller.ready) return;
    _controller.sync(
      snapshot: widget.data.displayedSnapshot,
      xray: widget.data.xray,
      layers: widget.data.layers,
      animations: widget.settings.animations,
    );
    if (_cameraReset != widget.data.cameraReset ||
        oldViewNeedsReset(widget.data.cameraView)) {
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
    _target = _targetGoal.clone();
    final vm.Vector3 offset = raw - _target;
    _distance = offset.length.clamp(7, 23);
    _azimuth = math.atan2(-offset.x, -offset.z);
    _polar = math.asin((offset.y / _distance).clamp(-1, 1));
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
      up: widget.data.cameraView == CameraView.top
          ? vm.Vector3(0, 0, 1)
          : vm.Vector3(0, 1, 0),
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
  }

  void _onTapUp(TapUpDetails details) {
    if (!widget.data.canPlace || !_ready || _size.isEmpty) return;
    final vm.Ray ray = _camera().screenPointToRay(details.localPosition, _size);
    final ({int x, int y})? column = _controller.pick(ray);
    if (column != null) widget.onPlace(column.x, column.y);
  }

  void _onScaleStart(ScaleStartDetails details) => _startDistance = _distance;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      _distance = (_startDistance / details.scale).clamp(7, 23);
    } else if (_size.height > 0) {
      _azimuth -= details.focalPointDelta.dx / _size.height * math.pi * .65;
      _polar =
          (_polar - details.focalPointDelta.dy / _size.height * math.pi * .65)
              .clamp(.001, math.pi / 2.16);
    }
    _targetGoal = _target.clone();
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
      return const ColoredBox(
        color: Color(0xFFE8E5DF),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Не удалось загрузить 3D-поле.\nПерезапустите приложение.',
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: fs.SceneView(
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
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _controller.dispose();
    super.dispose();
  }
}
