import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:four3/src/feature/appearance/data/skin_image_cache.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';
import 'package:four3/src/feature/appearance/service/skin_texture_painter.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/game/service/victory_presentation.dart';
import 'package:vector_math/vector_math.dart' as vm;

final class GameSceneController {
  new({SkinImageCache? imageCache})
    : _texturePainter = imageCache == null
          ? null
          : SkinTexturePainter(imageCache);

  static const spacing = 1.09;
  static const step = 0.5;
  static const firstHeight = 0.365;

  final fs.Scene scene = fs.Scene();
  final SkinTexturePainter? _texturePainter;
  final Map<int, _PieceVisual> _pieces = {};
  final List<fs.Node> _pickNodes = [];
  final List<_BoardMaterial> _boardMaterials = [];
  final List<_BoardDot> _boardDots = [];
  _PieceVisual? _ghost;
  int? _ghostColumn;
  fs.Node? _invalidColumnRoot;
  ({int x, int y})? _invalidColumn;
  late final fs.MeshGeometry _pieceGeometry;
  GameSnapshot? _snapshot;
  List<int> _layers = const [0, 1, 2, 3, 4];
  bool _xray = false;
  bool _animations = true;
  bool _introduction = false;
  bool _victoryAnimated = false;
  bool _ready = false;
  bool _disposed = false;
  Skin _skin = builtinSkins[1];
  _GpuArtwork? _artwork;
  int _skinGeneration = 0;

  bool get ready => _ready;
  ({int x, int y})? get invalidColumn => _invalidColumn;

  Future<void> initialize([Skin? skin]) async {
    _skin = skin ?? _skin;
    await fs.Scene.initializeStaticResources();
    _configureLighting();
    _pieceGeometry = _makePieceGeometry();
    final fs.Node board = await fs.loadScene('assets/models/four-board.glb');
    if (_disposed) return;
    board.name = 'board';
    _prepareBoard(board);
    scene.add(board);
    _addBoardDots();
    _addPickGeometry();
    _ready = true;
    _applyPalette();
    unawaited(applySkin(_skin));
  }

  Future<void> applySkin(Skin skin) async {
    if (_disposed) return;
    _skin = skin;
    final int generation = ++_skinGeneration;
    _artwork = null;
    if (_ready) _applyPalette();
    final SkinTexturePainter? painter = _texturePainter;
    if (painter == null) return;
    final bool hasImages = skin.design?.imageIds.isNotEmpty ?? false;
    SkinArtwork? initial;
    try {
      initial = await painter.paint(skin, preloadImages: false);
    } on Object {
      return;
    }
    if (initial == null) return;
    if (!await _installArtwork(initial, generation) || !hasImages) return;
    SkinArtwork? hydrated;
    try {
      hydrated = await painter.paint(skin);
    } on Object {
      return;
    }
    if (hydrated != null) await _installArtwork(hydrated, generation);
  }

  Future<bool> _installArtwork(SkinArtwork painted, int generation) async {
    if (_disposed || generation != _skinGeneration) {
      painted.dispose();
      return false;
    }
    try {
      final List<fs.Texture2D> textures = await Future.wait<fs.Texture2D>([
        for (final surface in SkinSurface.values)
          fs.Texture2D.fromImage(painted[surface]),
      ]);
      final fs.Texture2D? metallicRoughness = painted.metallicRoughness == null
          ? null
          : await fs.Texture2D.fromImage(
              painted.metallicRoughness!,
              content: fs.TextureContent.data,
            );
      if (_disposed || generation != _skinGeneration) return false;
      _artwork = _GpuArtwork({
        for (var index = 0; index < SkinSurface.values.length; index++)
          SkinSurface.values[index]: textures[index],
      }, metallicRoughness: metallicRoughness);
      if (_ready) _applyPalette();
      return true;
    } on Object {
      // Palette updates remain usable even when texture generation fails.
      return false;
    } finally {
      painted.dispose();
    }
  }

  void sync({
    required GameSnapshot snapshot,
    required bool xray,
    required List<int> layers,
    required bool animations,
    bool victoryAnimated = false,
    bool introduction = false,
  }) {
    if (!_ready) return;
    _snapshot = snapshot;
    _xray = xray;
    _layers = layers;
    _animations = animations;
    _victoryAnimated = victoryAnimated;
    _introduction = introduction;
    _updatePickGeometry();
    for (var index = 0; index < _boardDots.length; index++) {
      _boardDots[index].node.visible = snapshot.heights[index] == 0;
    }
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

  void tick(
    double elapsedSeconds,
    double deltaSeconds, {
    VictoryProgress? victory,
  }) {
    if (!_ready || _snapshot == null) return;
    for (final _PieceVisual visual in _pieces.values) {
      final double age = elapsedSeconds - visual.createdAt;
      final bool latest = visual.move.index == _snapshot!.history.length - 1;
      final double fall = victory != null && latest
          ? victory.fallOffset
          : _animations && !_introduction && latest && !_victoryAnimated
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
      if (victory != null) {
        visual.opacity = _xray
            ? .43
            : visual.winner
            ? 1
            : 1 - .48 * victory.dimProgress;
        visual.opacityFrom = visual.opacity;
        visual.targetOpacity = visual.opacity;
        visual.opacityElapsed = opacityDuration;
      } else if (visual.opacityElapsed < opacityDuration) {
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
      final double ringOpacity = victory != null && visual.winner
          ? renderedOpacity * victory.ringProgress
          : renderedOpacity;
      _opacity(visual.ringMaterial, ringOpacity);
      visual.ring.visible = victory != null
          ? visual.winner && victory.ringProgress > 0
          : visual.winner || latest;
      if (visual.winner && _animations) {
        final double strength = victory == null
            ? .6 + math.sin(elapsedSeconds * 3) * .3
            : .6 +
                  math.sin(
                        math.max(
                              0,
                              elapsedSeconds -
                                  visual.createdAt -
                                  (winCameraDuration + winFallDuration)
                                          .inMilliseconds /
                                      1000,
                            ) *
                            1.8,
                      ) *
                      .12;
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
    visual.opacity = .23;
    visual.opacityFrom = .23;
    visual.targetOpacity = .23;
    visual.opacityInitialized = true;
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

  void showInvalidColumn(int x, int y) {
    final GameSnapshot? snapshot = _snapshot;
    if (snapshot == null ||
        !GameEngine.coordinate(x) ||
        !GameEngine.coordinate(y) ||
        snapshot.heights[y * GameEngine.size + x] < GameEngine.size) {
      hideInvalidColumn();
      return;
    }
    final ({int x, int y}) column = (x: x, y: y);
    if (_invalidColumn == column && _invalidColumnRoot != null) return;
    hideInvalidColumn();

    final vm.Vector4 color = _linearColor(0xDB584B);
    final fs.PhysicallyBasedMaterial baseMaterial =
        _pbr(color.clone(), roughness: .36, metallic: .35)
          ..emissiveFactor = color.clone()
          ..emissiveStrength = .2;
    final fs.UnlitMaterial topMaterial = fs.UnlitMaterial()
      ..baseColorFactor = color.clone();
    final fs.Node root = fs.Node(name: 'invalid_column_${x}_$y')
      ..position = vm.Vector3((x - 2) * spacing, 0, (y - 2) * spacing);
    final fs.Node base =
        fs.Node(
            mesh: fs.Mesh(
              fs.TorusGeometry(
                radius: .49,
                tubeRadius: .01,
                radialSegments: 64,
                tubularSegments: 8,
              ),
              baseMaterial,
            ),
          )
          ..position = vm.Vector3(0, .173, 0)
          ..castsShadows = false;
    final int height = snapshot.heights[y * GameEngine.size + x];
    final fs.Node top =
        fs.Node(
            mesh: fs.Mesh(
              fs.TorusGeometry(
                radius: .42,
                tubeRadius: .025,
                radialSegments: 40,
                tubularSegments: 8,
              ),
              topMaterial,
            ),
          )
          ..position = vm.Vector3(0, .13 + height * step, 0)
          ..castsShadows = false;
    root
      ..add(base)
      ..add(top);
    scene.add(root);
    _invalidColumnRoot = root;
    _invalidColumn = column;
  }

  void hideInvalidColumn() {
    final fs.Node? root = _invalidColumnRoot;
    if (root != null) scene.remove(root);
    _invalidColumnRoot = null;
    _invalidColumn = null;
  }

  vm.Vector3 winningTarget() {
    final List<List<BoardPosition>> lines = _snapshot?.winningLines ?? const [];
    final List<BoardPosition> points = lines.expand((line) => line).toList();
    if (points.isEmpty) return vm.Vector3(0, .25, 0);
    final result = vm.Vector3.zero();
    for (final point in points) {
      result.add(position(point));
    }
    result.scale(1 / points.length);
    return result;
  }

  static vm.Vector3 position(BoardPosition position) => vm.Vector3(
    (position.x - 2) * spacing,
    firstHeight + position.z * step,
    (position.y - 2) * spacing,
  );

  _PieceVisual _createPiece(GameMove move) {
    final dark = move.player == Player.one;
    final PiecePalette palette = dark
        ? _skin.palette.dark
        : _skin.palette.light;
    final fs.PhysicallyBasedMaterial bodyMaterial = _pbr(
      _linearHex(palette.body),
      roughness: dark ? .34 : .48,
      metallic: dark ? .2 : .08,
    );
    final fs.PhysicallyBasedMaterial capMaterial = _pbr(
      _linearHex(palette.cap),
      roughness: .52,
    );
    final symbolMaterial = fs.UnlitMaterial()
      ..baseColorFactor = _linearHex(palette.mark, .85)
      ..alphaMode = fs.AlphaMode.blend;
    final fs.PhysicallyBasedMaterial ringMaterial =
        _pbr(_linearHex(_skin.palette.accent), roughness: 1, metallic: 0)
          ..emissiveFactor = _linearHex(_skin.palette.accent)
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
    final visual = _PieceVisual(
      root: root,
      move: move,
      dark: dark,
      bodyMaterial: bodyMaterial,
      capMaterial: capMaterial,
      symbolMaterial: symbolMaterial,
      ringMaterial: ringMaterial,
      ring: ring,
      symbol: symbol,
      createdAt: _clockSeconds,
      introductionDelay: _introduction
          ? .45 + (move.x + move.y) * .055 + move.z * .14
          : null,
    );
    _applyPieceSkin(visual);
    return visual;
  }

  void _prepareBoard(fs.Node board) {
    for (final fs.Node node in board.meshNodes) {
      for (final fs.MeshPrimitive primitive in node.mesh!.primitives) {
        final fs.Material material = primitive.material;
        if (material is! fs.PhysicallyBasedMaterial) continue;
        _boardMaterials.add(
          _BoardMaterial(
            material: material,
            originalColor: material.baseColorFactor.clone(),
            originalRoughness: material.roughnessFactor,
            originalMetalness: material.metallicFactor,
          ),
        );
        if (material.name.startsWith('Porcelain') &&
            primitive.geometry.isReadable) {
          final fs.MeshData data = primitive.geometry.extractMeshData();
          final Float32List positions = data.positions;
          final Float32List texCoords = planarTexCoords(positions);
          primitive.geometry = fs.MeshGeometry.fromArrays(
            positions: positions,
            normals: data.normals,
            texCoords: texCoords,
            colors: data.colors,
            tangents: data.tangents,
            indices: data.indices,
            primitiveType: data.primitiveType,
          );
        }
      }
    }
  }

  void _addBoardDots() {
    final geometry = fs.DiscGeometry(radius: .025, segments: 16);
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        final fs.UnlitMaterial material = fs.UnlitMaterial()
          ..baseColorFactor = _linearHex(_skin.palette.board.dot);
        final fs.Node node = fs.Node(mesh: fs.Mesh(geometry, material))
          ..name = 'board_dot_${x}_$y'
          ..position = vm.Vector3((x - 2) * spacing, .108, (y - 2) * spacing)
          ..castsShadows = false;
        _boardDots.add(_BoardDot(node: node, material: material));
        scene.add(node);
      }
    }
  }

  void _applyPalette() {
    final _GpuArtwork? artwork = _artwork;
    final SurfaceDesign? boardDesign = _surfaceDesign(SkinSurface.board);
    for (final _BoardMaterial entry in _boardMaterials) {
      final fs.PhysicallyBasedMaterial material = entry.material;
      if (material.name.startsWith('Porcelain')) {
        material
          ..baseColorFactor = artwork == null
              ? _linearHex(_skin.palette.board.body)
              : _linearColor(0xFFFFFF)
          ..baseColorTexture = artwork?[SkinSurface.board]
          ..metallicRoughnessTexture = artwork?.metallicRoughness
          ..roughnessFactor =
              boardDesign?.roughness ??
              (artwork == null ? entry.originalRoughness : .3)
          ..metallicFactor =
              boardDesign?.metalness ??
              (artwork == null ? entry.originalMetalness : .86);
      } else if (material.name == 'Satin champagne') {
        material
          ..baseColorFactor = _linearHex(_skin.palette.board.rim)
          ..roughnessFactor = artwork == null ? entry.originalRoughness : .26
          ..metallicFactor = artwork == null ? entry.originalMetalness : .85;
      } else if (material.name == 'Anodized graphite') {
        material.baseColorFactor = artwork == null
            ? entry.originalColor.clone()
            : _linearColor(0x101C23);
      } else if (material.name == 'Cobalt enamel') {
        material.baseColorFactor = _linearHex(_skin.palette.accent);
      }
    }
    for (final _BoardDot dot in _boardDots) {
      dot.material.baseColorFactor = _linearHex(_skin.palette.board.dot);
    }
    for (final _PieceVisual visual in _pieces.values) {
      _applyPieceSkin(visual);
    }
    if (_ghost case final ghost?) _applyPieceSkin(ghost);
  }

  SurfaceDesign? _surfaceDesign(SkinSurface surface) => _skin.design?[surface];

  void _applyPieceSkin(_PieceVisual visual) {
    final PiecePalette palette = visual.dark
        ? _skin.palette.dark
        : _skin.palette.light;
    final SkinSurface bodySurface = visual.dark
        ? SkinSurface.darkBody
        : SkinSurface.lightBody;
    final SkinSurface capSurface = visual.dark
        ? SkinSurface.darkCap
        : SkinSurface.lightCap;
    final SurfaceDesign? bodyDesign = _surfaceDesign(bodySurface);
    final SurfaceDesign? capDesign = _surfaceDesign(capSurface);
    final _GpuArtwork? artwork = _artwork;
    visual.bodyMaterial
      ..baseColorFactor = artwork == null
          ? _linearHex(palette.body, visual.opacity)
          : _linearColor(0xFFFFFF, visual.opacity)
      ..baseColorTexture = artwork?[bodySurface]
      ..roughnessFactor = bodyDesign?.roughness ?? (visual.dark ? .34 : .48)
      ..metallicFactor = bodyDesign?.metalness ?? (visual.dark ? .2 : .08);
    visual.capMaterial
      ..baseColorFactor = artwork == null
          ? _linearHex(palette.cap, visual.opacity)
          : _linearColor(0xFFFFFF, visual.opacity)
      ..baseColorTexture = artwork?[capSurface]
      ..roughnessFactor = capDesign?.roughness ?? (artwork == null ? .52 : .48)
      ..metallicFactor = capDesign?.metalness ?? (artwork == null ? 0 : .12);
    visual.symbolMaterial.baseColorFactor = _linearHex(
      palette.mark,
      visual.opacity * .85,
    );
    final bool hasArtwork = _skin.artwork == 'nocturne';
    visual.symbol.visible = !(capDesign?.decorated ?? false) && !hasArtwork;
    visual.ringMaterial
      ..baseColorFactor = _linearHex(
        _skin.palette.accent,
        visual.move.index == -1 ? .8 : visual.opacity,
      )
      ..emissiveFactor = _linearHex(_skin.palette.accent);
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
      final double opacity = _xray ? .43 : 1.0;
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
      visual.ring.visible =
          !_victoryAnimated && (visual.winner || visual.move.index == latest);
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
      node.raycastable = true;
    }
  }

  static int displayedHeight(int height, List<int> layers) {
    var result = 0;
    for (final layer in layers) {
      if (layer < height) result = math.max(result, layer + 1);
    }
    return result;
  }

  static Float32List planarTexCoords(Float32List positions) {
    if (positions.length % 3 != 0) {
      throw ArgumentError.value(positions.length, 'positions');
    }
    if (positions.isEmpty) return Float32List(0);
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minZ = double.infinity;
    double maxZ = double.negativeInfinity;
    for (var index = 0; index < positions.length; index += 3) {
      minX = math.min(minX, positions[index]);
      maxX = math.max(maxX, positions[index]);
      minZ = math.min(minZ, positions[index + 2]);
      maxZ = math.max(maxZ, positions[index + 2]);
    }
    final double width = math.max(.0001, maxX - minX);
    final double depth = math.max(.0001, maxZ - minZ);
    final texCoords = Float32List(positions.length ~/ 3 * 2);
    for (var vertex = 0; vertex < positions.length ~/ 3; vertex++) {
      texCoords[vertex * 2] = (positions[vertex * 3] - minX) / width;
      texCoords[vertex * 2 + 1] =
          1 - (positions[vertex * 3 + 2] - minZ) / depth;
    }
    return texCoords;
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

  static vm.Vector4 _linearHex(String value, [double alpha = 1]) =>
      _linearColor(int.parse(value.substring(1), radix: 16), alpha);

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
    const int columns = segments + 1;
    final positions = Float32List(profile.length * columns * 3);
    final texCoords = Float32List(profile.length * columns * 2);
    var cursor = 0;
    var texCursor = 0;
    for (var row = 0; row < profile.length; row++) {
      final (double, double) point = profile[row];
      for (var segment = 0; segment <= segments; segment++) {
        final double angle = segment / segments * math.pi * 2;
        positions[cursor++] = point.$1 * math.cos(angle);
        positions[cursor++] = point.$2;
        positions[cursor++] = point.$1 * math.sin(angle);
        texCoords[texCursor++] = segment / segments;
        texCoords[texCursor++] = row / (profile.length - 1);
      }
    }
    final indices = <int>[];
    for (var row = 0; row < profile.length - 1; row++) {
      for (var segment = 0; segment < segments; segment++) {
        final int a = row * columns + segment;
        final int b = row * columns + segment + 1;
        final int c = (row + 1) * columns + segment;
        final int d = (row + 1) * columns + segment + 1;
        indices.addAll([a, c, b, b, c, d]);
      }
    }
    return fs.MeshGeometry.fromArrays(
      positions: positions,
      texCoords: texCoords,
      indices: indices,
    );
  }

  void dispose() {
    _disposed = true;
    _skinGeneration++;
    _ghost = null;
    _invalidColumnRoot = null;
    _invalidColumn = null;
    scene.removeAll();
  }
}

final class _PieceVisual {
  new({
    required this.root,
    required this.move,
    required this.dark,
    required this.bodyMaterial,
    required this.capMaterial,
    required this.symbolMaterial,
    required this.ringMaterial,
    required this.ring,
    required this.symbol,
    required this.createdAt,
    required this.introductionDelay,
  });
  final fs.Node root;
  final GameMove move;
  final bool dark;
  final fs.PhysicallyBasedMaterial bodyMaterial;
  final fs.PhysicallyBasedMaterial capMaterial;
  final fs.UnlitMaterial symbolMaterial;
  final fs.PhysicallyBasedMaterial ringMaterial;
  final fs.Node ring;
  final fs.Node symbol;
  final double createdAt;
  final double? introductionDelay;
  double opacity = 1;
  double opacityFrom = 1;
  double targetOpacity = 1;
  double opacityElapsed = GameSceneController.opacityDuration;
  bool opacityInitialized = false;
  bool winner = false;
}

final class _BoardMaterial {
  const new({
    required this.material,
    required this.originalColor,
    required this.originalRoughness,
    required this.originalMetalness,
  });

  final fs.PhysicallyBasedMaterial material;
  final vm.Vector4 originalColor;
  final double originalRoughness;
  final double originalMetalness;
}

final class _BoardDot {
  const new({required this.node, required this.material});

  final fs.Node node;
  final fs.UnlitMaterial material;
}

final class _GpuArtwork {
  const new(this.textures, {this.metallicRoughness});

  final Map<SkinSurface, fs.Texture2D> textures;
  final fs.Texture2D? metallicRoughness;

  fs.Texture2D operator [](SkinSurface surface) => textures[surface]!;
}
