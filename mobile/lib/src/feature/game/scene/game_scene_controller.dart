import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:vector_math/vector_math.dart' as vm;

final class GameSceneController {
  static const spacing = 1.09;
  static const step = 0.5;
  static const firstHeight = 0.365;

  final fs.Scene scene = fs.Scene();
  final Map<int, _PieceVisual> _pieces = {};
  final List<fs.Node> _pickNodes = [];
  _PieceVisual? _ghost;
  int? _ghostColumn;
  late final fs.MeshGeometry _pieceGeometry;
  GameSnapshot? _snapshot;
  List<int> _layers = const [0, 1, 2, 3, 4];
  bool _xray = false;
  bool _animations = true;
  bool _introduction = false;
  bool _ready = false;

  bool get ready => _ready;

  Future<void> initialize() async {
    await fs.Scene.initializeStaticResources();
    _configureLighting();
    _pieceGeometry = _makePieceGeometry();
    final fs.Node board = await fs.loadScene('assets/models/four-board.glb');
    board.name = 'board';
    scene.add(board);
    _addPickGeometry();
    _ready = true;
  }

  void sync({
    required GameSnapshot snapshot,
    required bool xray,
    required List<int> layers,
    required bool animations,
    bool introduction = false,
  }) {
    if (!_ready) return;
    _snapshot = snapshot;
    _xray = xray;
    _layers = layers;
    _animations = animations;
    _introduction = introduction;
    _updatePickGeometry();
    final Map<int, GameMove> nextMoves = {
      for (final GameMove move in snapshot.history) move.index: move,
    };
    final Set<int> stale = staleMoveIndices(
      existing: _pieces.values.map((visual) => visual.move),
      next: nextMoves.values,
    );
    for (final int index in stale) {
      scene.remove(_pieces.remove(index)!.root);
    }
    for (final GameMove move in snapshot.history) {
      _pieces.putIfAbsent(move.index, () {
        final _PieceVisual visual = _createPiece(move);
        scene.add(visual.root);
        return visual;
      });
    }
    _updatePieceAppearance();
  }

  void tick(double elapsedSeconds, double deltaSeconds) {
    if (!_ready || _snapshot == null) return;
    for (final _PieceVisual visual in _pieces.values) {
      final double age = elapsedSeconds - visual.createdAt;
      final double fall =
          _animations &&
              !_introduction &&
              visual.move.index == _snapshot!.history.length - 1
          ? fallingOffset(age)
          : 0;
      final vm.Vector3 base = position(visual.move.position);
      var introFall = 0.0;
      var entranceOpacity = 1.0;
      final double? introductionDelay = visual.introductionDelay;
      if (_animations && introductionDelay != null) {
        final double progress = ((age - introductionDelay) / .8).clamp(0, 1);
        introFall = .7 * math.pow(1 - progress, 3);
        final double fade = math.min(1, progress * 4);
        entranceOpacity = fade * fade * (3 - 2 * fade);
        visual.root.visible =
            _layers.contains(visual.move.z) && age >= introductionDelay;
      }
      visual.root.position = vm.Vector3(
        base.x,
        base.y + fall + introFall,
        base.z,
      );
      if (visual.opacityElapsed < opacityDuration) {
        visual.opacityElapsed = math.min(
          opacityDuration,
          visual.opacityElapsed + deltaSeconds,
        );
        visual.opacity = opacityAt(
          from: visual.opacityFrom,
          target: visual.targetOpacity,
          elapsed: visual.opacityElapsed,
          animations: _animations,
        );
      }
      final double renderedOpacity = visual.opacity * entranceOpacity;
      _opacity(visual.bodyMaterial, renderedOpacity);
      _opacity(visual.capMaterial, renderedOpacity);
      visual.symbolMaterial.baseColorFactor.a = renderedOpacity * .85;
      visual.symbolMaterial.alphaMode = renderedOpacity < 1
          ? fs.AlphaMode.blend
          : fs.AlphaMode.opaque;
      _opacity(visual.ringMaterial, renderedOpacity);
      if (visual.winner && _animations) {
        final double strength = .6 + math.sin(elapsedSeconds * 3) * .3;
        visual.ringMaterial.emissiveStrength = strength;
      }
    }
  }

  ({int x, int y})? pick(vm.Ray ray) {
    if (!_ready) return null;
    final fs.SceneRaycastHit? hit = scene.raycast(
      ray,
      where: (node) => node.name.startsWith('slot_'),
    );
    if (hit == null) return null;
    final List<String> parts = hit.node.name.split('_');
    if (parts.length != 3) return null;
    return (x: int.parse(parts[1]), y: int.parse(parts[2]));
  }

  void showGhost(int x, int y) {
    final GameSnapshot? snapshot = _snapshot;
    if (snapshot == null || snapshot.status != GameStatus.playing) {
      hideGhost();
      return;
    }
    final int column = y * 5 + x;
    final int height = snapshot.heights[column];
    if (height >= 5 || !_layers.contains(height)) {
      hideGhost();
      return;
    }
    if (_ghostColumn == column && _ghost != null) return;
    hideGhost();
    final _PieceVisual visual = _createPiece(
      GameMove(
        x: x,
        y: y,
        z: height,
        player: snapshot.currentPlayer,
        index: -1,
      ),
    );
    visual.root.position = visual.root.position + vm.Vector3(0, .045, 0);
    _opacity(visual.bodyMaterial, .23);
    _opacity(visual.capMaterial, .23);
    visual.symbolMaterial.baseColorFactor.a = .23 * .85;
    visual.symbolMaterial.alphaMode = fs.AlphaMode.blend;
    _opacity(visual.ringMaterial, .8);
    visual.ring.visible = true;
    scene.add(visual.root);
    _ghost = visual;
    _ghostColumn = column;
  }

  void hideGhost() {
    final _PieceVisual? visual = _ghost;
    if (visual != null) scene.remove(visual.root);
    _ghost = null;
    _ghostColumn = null;
  }

  vm.Vector3 winningTarget() {
    final List<List<BoardPosition>> lines = _snapshot?.winningLines ?? const [];
    final List<BoardPosition> points = lines.expand((line) => line).toList();
    if (points.isEmpty) return vm.Vector3(0, .25, 0);
    final result = vm.Vector3.zero();
    for (final point in points) {
      result.add(position(point));
    }
    result.scale(.42 / points.length);
    return result;
  }

  static vm.Vector3 position(BoardPosition position) => vm.Vector3(
    (position.x - 2) * spacing,
    firstHeight + position.z * step,
    (position.y - 2) * spacing,
  );

  _PieceVisual _createPiece(GameMove move) {
    final dark = move.player == Player.one;
    final fs.PhysicallyBasedMaterial bodyMaterial = _pbr(
      dark ? _linearColor(0x24272C) : _linearColor(0xEEE4D2),
      roughness: dark ? .34 : .48,
      metallic: dark ? .2 : .08,
    );
    final fs.PhysicallyBasedMaterial capMaterial = _pbr(
      dark ? _linearColor(0x24292F) : _linearColor(0xF5EDDE),
      roughness: .52,
    );
    final symbolMaterial = fs.UnlitMaterial()
      ..baseColorFactor = dark
          ? _linearColor(0x858992, .85)
          : _linearColor(0x969286, .85)
      ..alphaMode = fs.AlphaMode.blend;
    final fs.PhysicallyBasedMaterial ringMaterial =
        _pbr(_linearColor(0x3661EE), roughness: 1, metallic: 0)
          ..emissiveFactor = _linearColor(0x3661EE)
          ..emissiveStrength = .35;

    final root = fs.Node(name: 'piece_${move.index}');
    root.position = position(move.position);
    // Put a new piece at the beginning of its fall before the first render.
    // Waiting for tick() produced one settled frame followed by a jump up.
    if (_animations &&
        !_introduction &&
        move.index == _snapshot!.history.length - 1) {
      root.position = root.position + vm.Vector3(0, fallingOffset(0), 0);
    }
    if (_introduction && _animations) root.visible = false;
    root.add(fs.Node(mesh: fs.Mesh(_pieceGeometry, bodyMaterial)));
    final cap = fs.Node(
      mesh: fs.Mesh(
        fs.CylinderGeometry(
          bottomRadius: .317,
          topRadius: .317,
          height: .009,
          radialSegments: 40,
        ),
        capMaterial,
      ),
    )..position = vm.Vector3(0, .2505, 0);
    root.add(cap);
    final fs.MeshGeometry symbolGeometry = dark
        ? fs.DiscGeometry(radius: .052, segments: 24)
        : fs.RingGeometry(innerRadius: .067, outerRadius: .085);
    final symbol = fs.Node(mesh: fs.Mesh(symbolGeometry, symbolMaterial))
      ..position = vm.Vector3(0, .258, 0);
    root.add(symbol);
    final ring = fs.Node(
      mesh: fs.Mesh(
        fs.TorusGeometry(
          radius: .353,
          tubeRadius: .012,
          radialSegments: 48,
          tubularSegments: 8,
        ),
        ringMaterial,
      ),
    )..position = vm.Vector3(0, .242, 0);
    root.add(ring);
    return _PieceVisual(
      root: root,
      move: move,
      bodyMaterial: bodyMaterial,
      capMaterial: capMaterial,
      symbolMaterial: symbolMaterial,
      ringMaterial: ringMaterial,
      ring: ring,
      createdAt: _clockSeconds,
      introductionDelay: _introduction
          ? .45 + (move.x + move.y) * .055 + move.z * .14
          : null,
    );
  }

  double _clockSeconds = 0;
  void setClock(double elapsedSeconds) => _clockSeconds = elapsedSeconds;

  void _updatePieceAppearance() {
    if (_snapshot == null) return;
    final Set<String> winners = {
      for (final point in _snapshot!.winningLines.expand((line) => line))
        '${point.x},${point.y},${point.z}',
    };
    final int latest = _snapshot!.history.isEmpty
        ? -1
        : _snapshot!.history.last.index;
    for (final _PieceVisual visual in _pieces.values) {
      final key = '${visual.move.x},${visual.move.y},${visual.move.z}';
      visual.winner = winners.contains(key);
      final bool introduced = switch (visual.introductionDelay) {
        final double delay =>
          !_animations || _clockSeconds - visual.createdAt >= delay,
        null => true,
      };
      visual.root.visible = _layers.contains(visual.move.z) && introduced;
      final double opacity = _xray
          ? .43
          : _snapshot!.status == GameStatus.won && !visual.winner
          ? .52
          : 1.0;
      if (!visual.opacityInitialized || !_animations) {
        visual.opacityInitialized = true;
        visual.opacity = opacity;
        visual.opacityFrom = opacity;
        visual.targetOpacity = opacity;
        visual.opacityElapsed = opacityDuration;
      } else if (visual.targetOpacity != opacity) {
        visual.opacityFrom = visual.opacity;
        visual.targetOpacity = opacity;
        visual.opacityElapsed = 0;
      }
      _opacity(visual.bodyMaterial, visual.opacity);
      _opacity(visual.capMaterial, visual.opacity);
      visual.symbolMaterial.baseColorFactor.a = visual.opacity * .85;
      visual.symbolMaterial.alphaMode = visual.opacity < 1
          ? fs.AlphaMode.blend
          : fs.AlphaMode.opaque;
      _opacity(visual.ringMaterial, visual.opacity);
      visual.ring.visible = visual.winner || visual.move.index == latest;
    }
  }

  static const double opacityDuration = .15;

  static Set<int> staleMoveIndices({
    required Iterable<GameMove> existing,
    required Iterable<GameMove> next,
  }) {
    final Map<int, GameMove> nextByIndex = {
      for (final GameMove move in next) move.index: move,
    };
    return {
      for (final GameMove move in existing)
        if (nextByIndex[move.index] != move) move.index,
    };
  }

  static double opacityAt({
    required double from,
    required double target,
    required double elapsed,
    required bool animations,
  }) {
    if (!animations) return target;
    final double progress = (elapsed / opacityDuration).clamp(0, 1);
    return from + (target - from) * progress;
  }

  void _addPickGeometry() {
    final material = fs.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 0)
      ..alphaMode = fs.AlphaMode.blend;
    final geometry = fs.CylinderGeometry(
      bottomRadius: .49,
      topRadius: .49,
      radialSegments: 16,
    );
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        final node =
            fs.Node(name: 'slot_${x}_$y', mesh: fs.Mesh(geometry, material))
              ..position = vm.Vector3(
                (x - 2) * spacing,
                .0775,
                (y - 2) * spacing,
              )
              ..scale = vm.Vector3(1, .155, 1)
              ..castsShadows = false;
        scene.add(node);
        _pickNodes.add(node);
      }
    }
  }

  void _updatePickGeometry() {
    final GameSnapshot? snapshot = _snapshot;
    if (snapshot == null || _pickNodes.length != 25) return;
    for (var column = 0; column < 25; column++) {
      final int x = column % 5;
      final int y = column ~/ 5;
      final int height = displayedHeight(snapshot.heights[column], _layers);
      final double pickHeight = .13 + height * step + .025;
      final fs.Node node = _pickNodes[column]
        ..position = vm.Vector3(
          (x - 2) * spacing,
          pickHeight / 2,
          (y - 2) * spacing,
        )
        ..scale = vm.Vector3(1, pickHeight, 1);
      node.raycastable = snapshot.heights[column] < 5;
    }
  }

  static int displayedHeight(int height, List<int> layers) {
    var result = 0;
    for (final layer in layers) {
      if (layer < height) result = math.max(result, layer + 1);
    }
    return result;
  }

  static double fallingOffset(double age) {
    if (age <= 0) return 2.2;
    if (age < .27) return 2.2 * (1 - math.pow(age / .27, 2));
    if (age < .41) {
      return math.sin(((age - .27) / .14) * math.pi) * .085;
    }
    return 0;
  }

  void _configureLighting() {
    // React Three Fiber defaults to ACES filmic. flutter_scene defaults to
    // PBR Neutral, which noticeably changes the highlights and warm colors.
    scene.toneMapping = fs.ToneMappingMode.aces;
    scene.exposure = 1;

    // Exact key/fill/rim setup from the web reference. The built-in studio
    // environment supplies the web ambient + hemisphere fill and reflections.
    _addDirectionalLight(
      position: vm.Vector3(-4, 9, 3),
      color: 0xFFF3DC,
      intensity: 2.4,
    );
    _addDirectionalLight(
      position: vm.Vector3(6, 4, -5),
      color: 0xDDE7FF,
      intensity: 1.4,
    );
    _addDirectionalLight(
      position: vm.Vector3(-4, 2, -4),
      color: 0xFFFFFF,
      intensity: .6,
    );
  }

  void _addDirectionalLight({
    required vm.Vector3 position,
    required int color,
    required double intensity,
  }) {
    final vm.Vector3 direction = -position
      ..normalize();
    final fs.DirectionalLight light = fs.DirectionalLight(
      direction: direction,
      color: _linearColor3(color),
      intensity: intensity,
    );
    scene.add(
      fs.Node(name: 'reference-light')
        ..addComponent(fs.DirectionalLightComponent.aimed(light, direction)),
    );
  }

  static vm.Vector4 _linearColor(int rgb, [double alpha = 1]) => vm.Vector4(
    _srgbChannel(rgb >> 16 & 0xFF),
    _srgbChannel(rgb >> 8 & 0xFF),
    _srgbChannel(rgb & 0xFF),
    alpha,
  );

  static vm.Vector3 _linearColor3(int rgb) => vm.Vector3(
    _srgbChannel(rgb >> 16 & 0xFF),
    _srgbChannel(rgb >> 8 & 0xFF),
    _srgbChannel(rgb & 0xFF),
  );

  static double _srgbChannel(int channel) {
    final double value = channel / 255;
    return value <= .04045
        ? value / 12.92
        : math.pow((value + .055) / 1.055, 2.4).toDouble();
  }

  fs.PhysicallyBasedMaterial _pbr(
    vm.Vector4 color, {
    double roughness = .45,
    double metallic = .1,
  }) => fs.PhysicallyBasedMaterial()
    ..baseColorFactor = color.clone()
    ..roughnessFactor = roughness
    ..metallicFactor = metallic;

  void _opacity(fs.PhysicallyBasedMaterial material, double opacity) {
    final vm.Vector4 color = material.baseColorFactor.clone()..a = opacity;
    material.baseColorFactor = color;
    material.alphaMode = opacity < 1 ? fs.AlphaMode.blend : fs.AlphaMode.opaque;
  }

  fs.MeshGeometry _makePieceGeometry() {
    const profile = <(double, double)>[
      (0, -.25),
      (.342, -.25),
      (.377, -.241),
      (.397, -.214),
      (.4, -.18),
      (.4, .175),
      (.394, .211),
      (.375, .237),
      (.342, .25),
      (0, .25),
    ];
    const segments = 48;
    final positions = Float32List(profile.length * segments * 3);
    var cursor = 0;
    for (final point in profile) {
      for (var segment = 0; segment < segments; segment++) {
        final double angle = segment / segments * math.pi * 2;
        positions[cursor++] = point.$1 * math.cos(angle);
        positions[cursor++] = point.$2;
        positions[cursor++] = point.$1 * math.sin(angle);
      }
    }
    final indices = <int>[];
    for (var row = 0; row < profile.length - 1; row++) {
      for (var segment = 0; segment < segments; segment++) {
        final int next = (segment + 1) % segments;
        final int a = row * segments + segment;
        final int b = row * segments + next;
        final int c = (row + 1) * segments + segment;
        final int d = (row + 1) * segments + next;
        indices.addAll([a, c, b, b, c, d]);
      }
    }
    return fs.MeshGeometry.fromArrays(positions: positions, indices: indices);
  }

  void dispose() {
    _ghost = null;
    scene.removeAll();
  }
}

final class _PieceVisual {
  new({
    required this.root,
    required this.move,
    required this.bodyMaterial,
    required this.capMaterial,
    required this.symbolMaterial,
    required this.ringMaterial,
    required this.ring,
    required this.createdAt,
    required this.introductionDelay,
  });
  final fs.Node root;
  final GameMove move;
  final fs.PhysicallyBasedMaterial bodyMaterial;
  final fs.PhysicallyBasedMaterial capMaterial;
  final fs.UnlitMaterial symbolMaterial;
  final fs.PhysicallyBasedMaterial ringMaterial;
  final fs.Node ring;
  final double createdAt;
  final double? introductionDelay;
  double opacity = 1;
  double opacityFrom = 1;
  double targetOpacity = 1;
  double opacityElapsed = GameSceneController.opacityDuration;
  bool opacityInitialized = false;
  bool winner = false;
}
