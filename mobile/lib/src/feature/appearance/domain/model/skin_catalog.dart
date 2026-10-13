import 'dart:convert';

import 'package:flutter/foundation.dart';

const String defaultRoomColor = '#ebeae7';

final RegExp _colorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');
final RegExp _customSkinPattern = RegExp(r'^custom-[a-f0-9]{32}$');
final RegExp _imageIdPattern = RegExp(r'^[a-f0-9]{64}$');
final RegExp _layerIdPattern = RegExp(r'^[a-zA-Z0-9_-]{1,48}$');

enum SkinSurface { board, darkCap, darkBody, lightCap, lightBody }

enum SkinPattern { none, celestial, botanical, artdeco, guilloche, marble }

enum SkinMotif { moon, sun, star, lotus, laurel, diamond, rings }

enum LayerPlacement { single, corners, grid }

final class PiecePalette {
  const new({required this.body, required this.cap, required this.mark});

  final String body;
  final String cap;
  final String mark;

  Map<String, Object?> toJson() => {'body': body, 'cap': cap, 'mark': mark};

  static PiecePalette? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null || !_exactKeys(map, const {'body', 'cap', 'mark'})) {
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
    if (map == null || !_exactKeys(map, const {'body', 'rim', 'dot'})) {
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
    if (!_exactKeys(map, const {'room', 'board', 'dark', 'light', 'accent'})) {
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
    final expected = <String>{
      'id',
      'kind',
      'x',
      'y',
      'size',
      'rotation',
      'opacity',
      'color',
      'tint',
      'placement',
      if (kind == 'motif') 'motif' else if (kind == 'image') 'imageId',
    };
    if ((kind != 'motif' && kind != 'image') || !_exactKeys(map, expected)) {
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
    'pattern': pattern.name,
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
        !_exactKeys(map, const {
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
    final SkinPattern? pattern = _enumByName(
      SkinPattern.values,
      map['pattern'],
    );
    final double? patternScale = _number(map['patternScale'], .5, 3);
    final double? patternOpacity = _number(map['patternOpacity'], 0, 1);
    final double? roughness = _number(map['roughness'], 0, 1);
    final double? metalness = _number(map['metalness'], 0, 1);
    final Object? rawLayers = map['layers'];
    if (pattern == null ||
        !_color(map['ink']) ||
        patternScale == null ||
        patternOpacity == null ||
        roughness == null ||
        metalness == null ||
        map['border'] is! bool ||
        rawLayers is! List<Object?> ||
        rawLayers.length > 12) {
      return null;
    }
    final List<DesignLayer?> layers = rawLayers
        .map(DesignLayer.fromJson)
        .toList();
    if (layers.any((layer) => layer == null)) return null;
    final List<DesignLayer> typed = layers.cast<DesignLayer>();
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
    if (map == null ||
        !_exactKeys(map, const {'version', 'surfaces'}) ||
        map['version'] != 1) {
      return null;
    }
    final Map<String, Object?>? raw = _record(map['surfaces']);
    if (raw == null ||
        !_exactKeys(
          raw,
          SkinSurface.values.map((value) => value.name).toSet(),
        )) {
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
    final allowed = {'id', 'name', 'builtin', 'palette', 'artwork', 'design'};
    if (map.keys.any((key) => !allowed.contains(key))) return null;
    final Object? id = map['id'];
    final Object? name = map['name'];
    final Object? builtin = map['builtin'];
    final SkinPalette? palette = SkinPalette.fromJson(map['palette']);
    final Object? artwork = map['artwork'];
    final SkinDesign? design = map.containsKey('design')
        ? SkinDesign.fromJson(map['design'])
        : null;
    final Skin? builtinDefinition = builtinSkins
        .where((skin) => skin.id == id)
        .firstOrNull;
    if (id is! String ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 48 ||
        builtin is! bool ||
        palette == null ||
        (builtinDefinition == null && !_customSkinPattern.hasMatch(id)) ||
        builtin != (builtinDefinition != null) ||
        (artwork != null && artwork != 'nocturne') ||
        (map.containsKey('design') && design == null)) {
      return null;
    }
    return Skin(
      id: id,
      name: name,
      builtin: builtin,
      palette: palette,
      artwork: artwork as String?,
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
  });

  final int revision;
  final String activeSkinId;
  final List<Skin> skins;

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

  static SkinCatalog? decode(String value) {
    try {
      return fromJson(jsonDecode(value));
    } on Object {
      return null;
    }
  }

  static SkinCatalog? fromJson(Object? value) {
    final Map<String, Object?>? map = _record(value);
    if (map == null ||
        !_exactKeys(map, const {
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
    final List<Skin?> parsed = rawSkins.map(Skin.fromJson).toList();
    if (parsed.any((skin) => skin == null)) return null;
    final List<Skin> skins = parsed.cast<Skin>().toList();
    for (final Skin builtin in builtinSkins) {
      if (!skins.any((skin) => skin.id == builtin.id)) skins.add(builtin);
    }
    if (skins.length < builtinSkins.length ||
        skins.length > builtinSkins.length + 32 ||
        skins.map((skin) => skin.id).toSet().length != skins.length ||
        !skins.any((skin) => skin.id == map['activeSkinId'])) {
      return null;
    }
    return SkinCatalog(
      revision: map['revision']! as int,
      activeSkinId: map['activeSkinId']! as String,
      skins: List.unmodifiable(skins),
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
]);

SkinCatalog defaultSkinCatalog() =>
    SkinCatalog(revision: 0, activeSkinId: 'coffee-board', skins: builtinSkins);

Map<String, Object?>? _record(Object? value) => value is Map<Object?, Object?>
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : null;

bool _exactKeys(Map<String, Object?> map, Set<String> keys) =>
    map.length == keys.length && map.keys.every(keys.contains);

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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
