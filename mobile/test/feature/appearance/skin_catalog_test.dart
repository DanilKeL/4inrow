import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';

void main() {
  test('default catalog contains the four web built-ins', () {
    final SkinCatalog catalog = defaultSkinCatalog();

    expect(catalog.activeSkinId, 'coffee-board');
    expect(
      catalog.skins.map((skin) => skin.id),
      containsAll(['classic', 'coffee-board', 'coffee-pieces', 'nocturne']),
    );
    expect(
      catalog.skins.firstWhere((skin) => skin.id == 'nocturne').artwork,
      'nocturne',
    );
  });

  test('legacy palettes without room are normalized', () {
    final Map<String, Object?> json = defaultSkinCatalog().toJson();
    for (final skin in json['skins']! as List<Object?>) {
      final map = skin! as Map<String, Object?>;
      (map['palette']! as Map<String, Object?>).remove('room');
    }

    final SkinCatalog? catalog = SkinCatalog.fromJson(json);

    expect(catalog, isNotNull);
    expect(
      catalog!.skins.map((skin) => skin.palette.room),
      everyElement(defaultRoomColor),
    );
  });

  test('new built-ins are appended to an older valid cache', () {
    final Map<String, Object?> json = defaultSkinCatalog().toJson();
    (json['skins']! as List<Object?>).removeWhere(
      (skin) => (skin! as Map<String, Object?>)['id'] == 'nocturne',
    );

    final SkinCatalog? catalog = SkinCatalog.fromJson(json);

    expect(catalog, isNotNull);
    expect(catalog!.skins.any((skin) => skin.id == 'nocturne'), isTrue);
  });

  test('design image ids are de-duplicated and extracted', () {
    const imageId =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final surfaceJson = <String, Object?>{
      'pattern': 'none',
      'ink': '#c8a970',
      'patternScale': 1,
      'patternOpacity': .65,
      'border': false,
      'roughness': .5,
      'metalness': 0,
      'layers': [
        {
          'id': 'image-one',
          'kind': 'image',
          'imageId': imageId,
          'x': .5,
          'y': .5,
          'size': .56,
          'rotation': 0,
          'opacity': 1,
          'color': '#c8a970',
          'tint': false,
          'placement': 'single',
        },
      ],
    };
    final SkinDesign? design = SkinDesign.fromJson({
      'version': 1,
      'surfaces': {
        for (final name in SkinSurface.values.map((surface) => surface.name))
          name: Map<String, Object?>.from(surfaceJson),
      },
    });

    expect(design, isNotNull);
    expect(design!.imageIds, {imageId});
  });

  test('malformed catalog and palette are rejected', () {
    expect(SkinCatalog.decode('{broken'), isNull);
    final Map<String, Object?> catalog = defaultSkinCatalog().toJson();
    catalog['unknown'] = true;
    expect(SkinCatalog.fromJson(catalog), isNull);

    final Map<String, Object?> badSkin = defaultSkinCatalog().skins.first
        .toJson();
    final palette = badSkin['palette']! as Map<String, Object?>;
    palette['room'] = 'white';
    expect(Skin.fromJson(badSkin), isNull);
  });
}
