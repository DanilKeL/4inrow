import 'dart:convert';

import 'package:flutter/foundation.dart';

const String defaultRoomColor = '#ebeae7';

final RegExp _colorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');
final RegExp _skinIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
final RegExp _imageIdPattern = RegExp(r'^[a-f0-9]{64}$');
final RegExp _layerIdPattern = RegExp(r'^[a-zA-Z0-9_-]{1,48}$');

enum SkinSurface { board, darkCap, darkBody, lightCap, lightBody }

enum SkinPattern {
  none,
  celestial,
  botanical,
  artdeco,
  guilloche,
  marble,
  gingham,
  sakuraWaves,
}

enum SkinMotif {
  moon,
  sun,
  star,
  lotus,
  laurel,
  diamond,
  rings,
  heart,
  bow,
  blossom,
  sakura,
  kitsune,
  crest,
}

String _patternName(SkinPattern pattern) => switch (pattern) {
  SkinPattern.sakuraWaves => 'sakura-waves',
  _ => pattern.name,
};

enum LayerPlacement { single, corners, grid }

final class PiecePalette {
  const new({required this.body, required this.cap, required this.mark});

  final String body;
  final String cap;
  final String mark;

  Map<String, Object?> toJson() => {'body': body, 'cap': cap, 'mark': mark};

  static PiecePalette? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null || !_hasKeys(map, const {'body', 'cap', 'mark'})) {
      return null;
    }
    if (!_color(map['body']) || !_color(map['cap']) || !_color(map['mark'])) {
      return null;
    }
    return PiecePalette(
      body: map['body']! as String,
      cap: map['cap']! as String,
      mark: map['mark']! as String,
    );
  }
}

final class BoardPalette {
  const new({required this.body, required this.rim, required this.dot});

  final String body;
  final String rim;
  final String dot;

  Map<String, Object?> toJson() => {'body': body, 'rim': rim, 'dot': dot};

  static BoardPalette? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null || !_hasKeys(map, const {'body', 'rim', 'dot'})) {
      return null;
    }
    if (!_color(map['body']) || !_color(map['rim']) || !_color(map['dot'])) {
      return null;
    }
    return BoardPalette(
      body: map['body']! as String,
      rim: map['rim']! as String,
      dot: map['dot']! as String,
    );
  }
}

final class SkinPalette {
  const new({
    required this.room,
    required this.board,
    required this.dark,
    required this.light,
    required this.accent,
  });

  final String room;
  final BoardPalette board;
  final PiecePalette dark;
  final PiecePalette light;
  final String accent;

  Map<String, Object?> toJson() => {
    'room': room,
    'board': board.toJson(),
    'dark': dark.toJson(),
    'light': light.toJson(),
    'accent': accent,
  };

  static SkinPalette? fromJson(Object? value) {
    final Map<String, Object?>? source = _record(value);
    if (source == null) return null;
    final map = <String, Object?>{'room': defaultRoomColor, ...source};
    if (!_hasKeys(map, const {'room', 'board', 'dark', 'light', 'accent'})) {
      return null;
    }
    final BoardPalette? board = BoardPalette.fromJson(map['board']);
    final PiecePalette? dark = PiecePalette.fromJson(map['dark']);
    final PiecePalette? light = PiecePalette.fromJson(map['light']);
    if (!_color(map['room']) ||
        !_color(map['accent']) ||
        board == null ||
        dark == null ||
        light == null) {
      return null;
    }
    return SkinPalette(
      room: map['room']! as String,
      board: board,
      dark: dark,
      light: light,
      accent: map['accent']! as String,
    );
  }
}

sealed class DesignLayer {
  const new({
    required this.id,
    required this.x,
    required this.y,
    required this.size,
    required this.rotation,
    required this.opacity,
    required this.color,
    required this.tint,
    required this.placement,
  });

  final String id;
  final double x;
  final double y;
  final double size;
  final double rotation;
  final double opacity;
  final String color;
  final bool tint;
  final LayerPlacement placement;

  Map<String, Object?> get baseJson => {
    'id': id,
    'x': x,
    'y': y,
    'size': size,
    'rotation': rotation,
    'opacity': opacity,
    'color': color,
    'tint': tint,
    'placement': placement.name,
  };

  Map<String, Object?> toJson();

  static DesignLayer? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null) return null;
    final Object? kind = map['kind'];
    if (kind != 'motif' && kind != 'image') {
      return null;
    }
    final Object? id = map['id'];
    final double? x = _number(map['x'], 0, 1);
    final double? y = _number(map['y'], 0, 1);
    final double? size = _number(map['size'], .05, 1);
    final double? rotation = _number(map['rotation'], -180, 180);
    final double? opacity = _number(map['opacity'], 0, 1);
    final LayerPlacement? placement = _enumByName(
      LayerPlacement.values,
      map['placement'],
    );
    if (id is! String ||
        !_layerIdPattern.hasMatch(id) ||
        x == null ||
        y == null ||
        size == null ||
        rotation == null ||
        opacity == null ||
        !_color(map['color']) ||
        map['tint'] is! bool ||
        placement == null) {
      return null;
    }
    if (kind == 'motif') {
      final SkinMotif? motif = _enumByName(SkinMotif.values, map['motif']);
      if (motif == null) return null;
      return MotifDesignLayer(
        id: id,
        motif: motif,
        x: x,
        y: y,
        size: size,
        rotation: rotation,
        opacity: opacity,
        color: map['color']! as String,
        tint: map['tint']! as bool,
        placement: placement,
      );
    }
    final Object? imageId = map['imageId'];
    if (imageId is! String || !_imageIdPattern.hasMatch(imageId)) return null;
    return ImageDesignLayer(
      id: id,
      imageId: imageId,
      x: x,
      y: y,
      size: size,
      rotation: rotation,
      opacity: opacity,
      color: map['color']! as String,
      tint: map['tint']! as bool,
      placement: placement,
    );
  }
}

final class MotifDesignLayer extends DesignLayer {
  const new({
    required super.id,
    required this.motif,
    required super.x,
    required super.y,
    required super.size,
    required super.rotation,
    required super.opacity,
    required super.color,
    required super.tint,
    required super.placement,
  });

  final SkinMotif motif;

  @override
  Map<String, Object?> toJson() => {
    ...baseJson,
    'kind': 'motif',
    'motif': motif.name,
  };
}

final class ImageDesignLayer extends DesignLayer {
  const new({
    required super.id,
    required this.imageId,
    required super.x,
    required super.y,
    required super.size,
    required super.rotation,
    required super.opacity,
    required super.color,
    required super.tint,
    required super.placement,
  });

  final String imageId;

  @override
  Map<String, Object?> toJson() => {
    ...baseJson,
    'kind': 'image',
    'imageId': imageId,
  };
}

final class SurfaceDesign {
  const new({
    required this.pattern,
    required this.ink,
    required this.patternScale,
    required this.patternOpacity,
    required this.border,
    required this.roughness,
    required this.metalness,
    required this.layers,
  });

  final SkinPattern pattern;
  final String ink;
  final double patternScale;
  final double patternOpacity;
  final bool border;
  final double roughness;
  final double metalness;
  final List<DesignLayer> layers;

  bool get decorated => pattern != SkinPattern.none || layers.isNotEmpty;

  Map<String, Object?> toJson() => {
    'pattern': _patternName(pattern),
    'ink': ink,
    'patternScale': patternScale,
    'patternOpacity': patternOpacity,
    'border': border,
    'roughness': roughness,
    'metalness': metalness,
    'layers': layers.map((layer) => layer.toJson()).toList(),
  };

  static SurfaceDesign? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null ||
        !_hasKeys(map, const {
          'pattern',
          'ink',
          'patternScale',
          'patternOpacity',
          'border',
          'roughness',
          'metalness',
          'layers',
        })) {
      return null;
    }
    final SkinPattern pattern = map['pattern'] == 'sakura-waves'
        ? SkinPattern.sakuraWaves
        : _enumByName(SkinPattern.values, map['pattern']) ?? SkinPattern.none;
    final double? patternScale = _number(map['patternScale'], .5, 3);
    final double? patternOpacity = _number(map['patternOpacity'], 0, 1);
    final double? roughness = _number(map['roughness'], 0, 1);
    final double? metalness = _number(map['metalness'], 0, 1);
    final Object? rawLayers = map['layers'];
    if (!_color(map['ink']) ||
        patternScale == null ||
        patternOpacity == null ||
        roughness == null ||
        metalness == null ||
        map['border'] is! bool ||
        rawLayers is! List<Object?> ||
        rawLayers.length > 12) {
      return null;
    }
    final List<DesignLayer> typed = rawLayers
        .map(DesignLayer.fromJson)
        .whereType<DesignLayer>()
        .toList();
    if (typed.map((layer) => layer.id).toSet().length != typed.length) {
      return null;
    }
    return SurfaceDesign(
      pattern: pattern,
      ink: map['ink']! as String,
      patternScale: patternScale,
      patternOpacity: patternOpacity,
      border: map['border']! as bool,
      roughness: roughness,
      metalness: metalness,
      layers: List.unmodifiable(typed),
    );
  }
}

final class SkinDesign {
  const new({required this.surfaces});

  final Map<SkinSurface, SurfaceDesign> surfaces;

  SurfaceDesign operator [](SkinSurface surface) => surfaces[surface]!;

  Set<String> get imageIds => {
    for (final surface in surfaces.values)
      for (final layer in surface.layers)
        if (layer is ImageDesignLayer) layer.imageId,
  };

  Map<String, Object?> toJson() => {
    'version': 1,
    'surfaces': {
      for (final entry in surfaces.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  static SkinDesign? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null || map['version'] != 1) {
      return null;
    }
    final Map<String, Object?>? raw = _record(map['surfaces']);
    if (raw == null ||
        !SkinSurface.values.every((surface) => raw.containsKey(surface.name))) {
      return null;
    }
    final surfaces = <SkinSurface, SurfaceDesign>{};
    for (final SkinSurface surface in SkinSurface.values) {
      final SurfaceDesign? design = SurfaceDesign.fromJson(raw[surface.name]);
      if (design == null) return null;
      surfaces[surface] = design;
    }
    final design = SkinDesign(surfaces: Map.unmodifiable(surfaces));
    return design.imageIds.length <= 16 ? design : null;
  }
}

final class Skin {
  const new({
    required this.id,
    required this.name,
    required this.builtin,
    required this.palette,
    this.artwork,
    this.design,
  });

  final String id;
  final String name;
  final bool builtin;
  final SkinPalette palette;
  final String? artwork;
  final SkinDesign? design;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'builtin': builtin,
    'palette': palette.toJson(),
    if (artwork != null) 'artwork': artwork,
    if (design != null) 'design': design!.toJson(),
  };

  static Skin? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null) return null;
    final Object? id = map['id'];
    final Object? name = map['name'];
    final Object? builtin = map['builtin'];
    final SkinPalette? palette = SkinPalette.fromJson(map['palette']);
    final Object? artwork = map['artwork'];
    final SkinDesign? design = SkinDesign.fromJson(map['design']);
    if (id is! String ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 48 ||
        builtin is! bool ||
        palette == null ||
        !_skinIdPattern.hasMatch(id) ||
        (artwork != null && artwork is! String)) {
      return null;
    }
    return Skin(
      id: id,
      name: name,
      builtin: builtin,
      palette: palette,
      artwork: artwork == 'nocturne' ? 'nocturne' : null,
      design: design,
    );
  }
}

@immutable
final class SkinCatalog {
  const new({
    required this.revision,
    required this.activeSkinId,
    required this.skins,
    this.sourceJson,
  });

  final int revision;
  final String activeSkinId;
  final List<Skin> skins;
  final String? sourceJson;

  Skin get activeSkin => skins.firstWhere(
    (skin) => skin.id == activeSkinId,
    orElse: () => builtinSkins[1],
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': revision,
    'activeSkinId': activeSkinId,
    'skins': skins.map((skin) => skin.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  String get cacheValue => sourceJson ?? encode();

  static SkinCatalog? decode(String value) {
    try {
      return fromJson(jsonDecode(value), sourceJson: value);
    } on Object {
      return null;
    }
  }

  static SkinCatalog? fromJson(Object? value, {String? sourceJson}) {
    final Map<String, Object?>? map = _record(value);
    if (map == null ||
        !_hasKeys(map, const {
          'schemaVersion',
          'revision',
          'activeSkinId',
          'skins',
        }) ||
        map['schemaVersion'] != 1 ||
        map['revision'] is! int ||
        (map['revision']! as int) < 0 ||
        (map['revision']! as int) > 9007199254740991 ||
        map['activeSkinId'] is! String ||
        map['skins'] is! List<Object?>) {
      return null;
    }
    final rawSkins = List<Object?>.from(map['skins']! as List<Object?>);
    final List<Skin> skins = rawSkins
        .map(Skin.fromJson)
        .whereType<Skin>()
        .toList();
    for (final Skin builtin in builtinSkins) {
      if (!skins.any((skin) => skin.id == builtin.id)) skins.add(builtin);
    }
    if (skins.length > 64 ||
        skins.map((skin) => skin.id).toSet().length != skins.length ||
        skins.isEmpty) {
      return null;
    }
    final String requestedActive = map['activeSkinId']! as String;
    final String active = skins.any((skin) => skin.id == requestedActive)
        ? requestedActive
        : 'coffee-board';
    return SkinCatalog(
      revision: map['revision']! as int,
      activeSkinId: active,
      skins: List.unmodifiable(skins),
      sourceJson: sourceJson,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SkinCatalog && encode() == other.encode();

  @override
  int get hashCode => encode().hashCode;
}

const SkinPalette classicPalette = SkinPalette(
  room: defaultRoomColor,
  board: BoardPalette(body: '#ede8dc', rim: '#aca18b', dot: '#979992'),
  dark: PiecePalette(body: '#24272c', cap: '#24292f', mark: '#858992'),
  light: PiecePalette(body: '#eee4d2', cap: '#f5edde', mark: '#969286'),
  accent: '#3661ee',
);

const String moonlitSakuraImageId =
    'bc22fbff3d878f25892d3bd09227dfe92c943adfabbbe88309788c40eceed6fb';

SurfaceDesign _surface({
  SkinPattern pattern = SkinPattern.none,
  String ink = '#c8a970',
  double patternScale = 1,
  double patternOpacity = .65,
  bool border = false,
  double roughness = .5,
  double metalness = 0,
  List<DesignLayer> layers = const [],
}) => SurfaceDesign(
  pattern: pattern,
  ink: ink,
  patternScale: patternScale,
  patternOpacity: patternOpacity,
  border: border,
  roughness: roughness,
  metalness: metalness,
  layers: List.unmodifiable(layers),
);

MotifDesignLayer _motif(
  String id,
  SkinMotif motif, {
  String color = '#c8a970',
  double x = .5,
  double y = .5,
  double size = .56,
  double opacity = 1,
  LayerPlacement placement = LayerPlacement.single,
}) => MotifDesignLayer(
  id: id,
  motif: motif,
  x: x,
  y: y,
  size: size,
  rotation: 0,
  opacity: opacity,
  color: color,
  tint: false,
  placement: placement,
);

SkinDesign pickmiDesign() => SkinDesign(
  surfaces: {
    SkinSurface.board: _surface(
      pattern: SkinPattern.gingham,
      ink: '#cf91a1',
      patternScale: 1.1,
      patternOpacity: .18,
      border: true,
      roughness: .34,
      metalness: .04,
      layers: [
        _motif(
          'corner-ribbons',
          SkinMotif.bow,
          color: '#b96583',
          size: .11,
          opacity: .9,
          placement: LayerPlacement.corners,
        ),
        _motif(
          'little-heart',
          SkinMotif.heart,
          color: '#bd718c',
          y: .927,
          size: .073,
        ),
        _motif(
          'porcelain-flowers',
          SkinMotif.blossom,
          color: '#fffbf3',
          size: .05,
          opacity: .72,
          placement: LayerPlacement.grid,
        ),
      ],
    ),
    SkinSurface.darkCap: _surface(
      ink: '#ffe8ec',
      border: true,
      roughness: .28,
      metalness: .02,
      layers: [
        _motif('cream-heart', SkinMotif.heart, color: '#ffecdf', size: .5),
        _motif(
          'tiny-sparkle',
          SkinMotif.star,
          color: '#ffe7e9',
          x: .74,
          y: .26,
          size: .11,
          opacity: .8,
        ),
      ],
    ),
    SkinSurface.lightCap: _surface(
      ink: '#bf8599',
      border: true,
      roughness: .3,
      metalness: .02,
      layers: [
        _motif('berry-bow', SkinMotif.bow, color: '#b65074', size: .58),
        _motif(
          'tiny-flower',
          SkinMotif.blossom,
          color: '#d58aa2',
          x: .27,
          y: .26,
          size: .13,
        ),
      ],
    ),
    SkinSurface.darkBody: _surface(
      pattern: SkinPattern.gingham,
      ink: '#fff0e8',
      patternScale: 1.5,
      patternOpacity: .12,
      border: true,
      roughness: .32,
      metalness: .03,
      layers: [
        _motif(
          'ribbon-hearts',
          SkinMotif.heart,
          color: '#ffdfdf',
          size: .13,
          opacity: .7,
          placement: LayerPlacement.grid,
        ),
      ],
    ),
    SkinSurface.lightBody: _surface(
      pattern: SkinPattern.gingham,
      ink: '#d694aa',
      patternScale: 1.5,
      patternOpacity: .24,
      border: true,
      roughness: .32,
      metalness: .03,
      layers: [
        _motif(
          'ribbon-flowers',
          SkinMotif.blossom,
          color: '#b97b96',
          size: .14,
          opacity: .75,
          placement: LayerPlacement.grid,
        ),
      ],
    ),
  },
);

SkinDesign animeDesign() => SkinDesign(
  surfaces: {
    SkinSurface.board: _surface(
      pattern: SkinPattern.sakuraWaves,
      ink: '#abcce2',
      patternScale: .95,
      patternOpacity: .6,
      border: true,
      roughness: .31,
      metalness: .22,
      layers: [
        _motif(
          'silver-seals',
          SkinMotif.crest,
          color: '#b3d7ef',
          size: .13,
          opacity: .85,
          placement: LayerPlacement.corners,
        ),
        _motif(
          'fox-seal',
          SkinMotif.kitsune,
          color: '#ee9fab',
          y: .935,
          size: .07,
        ),
      ],
    ),
    SkinSurface.darkCap: _surface(
      ink: '#c6e4f4',
      border: true,
      roughness: .3,
      metalness: .1,
      layers: [
        const ImageDesignLayer(
          id: 'moonlit-heroine',
          imageId: moonlitSakuraImageId,
          x: .5,
          y: .48,
          size: .86,
          rotation: 0,
          opacity: 1,
          color: '#ffffff',
          tint: false,
          placement: LayerPlacement.single,
        ),
      ],
    ),
    SkinSurface.lightCap: _surface(
      ink: '#93718e',
      border: true,
      roughness: .34,
      metalness: .08,
      layers: [
        _motif('silver-fox', SkinMotif.kitsune, color: '#34436b', size: .66),
        _motif(
          'sakura-mark',
          SkinMotif.sakura,
          color: '#d3779d',
          x: .74,
          y: .25,
          size: .18,
        ),
      ],
    ),
    SkinSurface.darkBody: _surface(
      pattern: SkinPattern.sakuraWaves,
      ink: '#a7cbe7',
      patternScale: 1.4,
      patternOpacity: .24,
      border: true,
      roughness: .34,
      metalness: .12,
      layers: [
        _motif(
          'falling-sakura',
          SkinMotif.sakura,
          color: '#ec9ab3',
          size: .2,
          opacity: .68,
          placement: LayerPlacement.grid,
        ),
      ],
    ),
    SkinSurface.lightBody: _surface(
      pattern: SkinPattern.sakuraWaves,
      ink: '#7d89b4',
      patternScale: 1.6,
      patternOpacity: .17,
      border: true,
      roughness: .35,
      metalness: .07,
      layers: [
        _motif(
          'moon-ribbon',
          SkinMotif.crest,
          color: '#4b5b87',
          size: .15,
          opacity: .6,
          placement: LayerPlacement.grid,
        ),
      ],
    ),
  },
);

final List<Skin> builtinSkins = List<Skin>.unmodifiable([
  Skin(
    id: 'classic',
    name: String.fromCharCodes(const <int>[
      0x041a,
      0x043b,
      0x0430,
      0x0441,
      0x0441,
      0x0438,
      0x043a,
      0x0430,
    ]),
    builtin: true,
    palette: classicPalette,
  ),
  Skin(
    id: 'coffee-board',
    name: String.fromCharCodes(const <int>[
      0x041a,
      0x043e,
      0x0444,
      0x0435,
      0x0439,
      0x043d,
      0x0430,
      0x044f,
      0x0020,
      0x0434,
      0x043e,
      0x0441,
      0x043a,
      0x0430,
    ]),
    builtin: true,
    palette: const SkinPalette(
      room: defaultRoomColor,
      board: BoardPalette(body: '#cbb394', rim: '#a58c6c', dot: '#826e55'),
      dark: PiecePalette(body: '#24272c', cap: '#24292f', mark: '#858992'),
      light: PiecePalette(body: '#eee4d2', cap: '#f5edde', mark: '#969286'),
      accent: '#3661ee',
    ),
  ),
  Skin(
    id: 'coffee-pieces',
    name: String.fromCharCodes(const <int>[
      0x041a,
      0x043e,
      0x0444,
      0x0435,
      0x0439,
      0x043d,
      0x044b,
      0x0435,
      0x0020,
      0x0444,
      0x0438,
      0x0448,
      0x043a,
      0x0438,
    ]),
    builtin: true,
    palette: const SkinPalette(
      room: defaultRoomColor,
      board: BoardPalette(body: '#ede8dc', rim: '#aca18b', dot: '#979992'),
      dark: PiecePalette(body: '#24272c', cap: '#24292f', mark: '#858992'),
      light: PiecePalette(body: '#cbb394', cap: '#dcc4a3', mark: '#8f7b60'),
      accent: '#3661ee',
    ),
  ),
  Skin(
    id: 'nocturne',
    name: String.fromCharCodes(const <int>[
      0x041d,
      0x043e,
      0x043a,
      0x0442,
      0x044e,
      0x0440,
      0x043d,
    ]),
    builtin: true,
    artwork: 'nocturne',
    palette: const SkinPalette(
      room: '#dce3e5',
      board: BoardPalette(body: '#172d38', rim: '#c8a970', dot: '#e1c98f'),
      dark: PiecePalette(body: '#122b35', cap: '#182f3a', mark: '#dec58a'),
      light: PiecePalette(body: '#e3dac5', cap: '#f2ead8', mark: '#76532e'),
      accent: '#d2b473',
    ),
  ),
  Skin(
    id: 'pickmi',
    name: String.fromCharCodes(const <int>[
      0x041f,
      0x0438,
      0x043a,
      0x043c,
      0x0438,
    ]),
    builtin: true,
    palette: const SkinPalette(
      room: '#eee6e8',
      board: BoardPalette(body: '#f4dce3', rim: '#c19aa3', dot: '#aa7389'),
      dark: PiecePalette(body: '#9f4263', cap: '#ae4c71', mark: '#ffe5e4'),
      light: PiecePalette(body: '#fff0dc', cap: '#fff7e9', mark: '#bd8297'),
      accent: '#d7749e',
    ),
    design: pickmiDesign(),
  ),
  Skin(
    id: 'sakura-nocturne',
    name: String.fromCharCodes(const <int>[
      0x041b,
      0x0443,
      0x043d,
      0x043d,
      0x0430,
      0x044f,
      0x0020,
      0x0441,
      0x0430,
      0x043a,
      0x0443,
      0x0440,
      0x0430,
    ]),
    builtin: true,
    palette: const SkinPalette(
      room: '#e1e4ec',
      board: BoardPalette(body: '#1b2848', rim: '#a9c8df', dot: '#8199c7'),
      dark: PiecePalette(body: '#1c2a4a', cap: '#26375c', mark: '#d7e2f9'),
      light: PiecePalette(body: '#e4e2f0', cap: '#f9ebed', mark: '#896780'),
      accent: '#f08dac',
    ),
    design: animeDesign(),
  ),
]);

SkinCatalog defaultSkinCatalog() =>
    SkinCatalog(revision: 0, activeSkinId: 'coffee-board', skins: builtinSkins);

Map<String, Object?>? _record(Object? value) => value is Map<Object?, Object?>
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : null;

bool _hasKeys(Map<String, Object?> map, Set<String> keys) =>
    keys.every(map.containsKey);

bool _color(Object? value) => value is String && _colorPattern.hasMatch(value);

double? _number(Object? value, double min, double max) {
  if (value is! num || !value.isFinite) return null;
  final double number = value.toDouble();
  return number >= min && number <= max ? number : null;
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
