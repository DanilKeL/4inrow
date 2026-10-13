import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/appearance/data/skin_image_cache.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';
import 'package:four3/src/feature/appearance/service/skin_texture_painter.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('planar UV maps X/Z bounds to the full texture', () {
    final Float32List uv = GameSceneController.planarTexCoords(
      Float32List.fromList([-2, 4, -3, 2, 8, 3]),
    );

    expect(uv, orderedEquals([0, 1, 1, 0]));
  });

  test('layer placements match single, corners, and grid rules', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'skin-painter-test',
    );
    final cache = SkinImageCache(
      baseUri: Uri.parse('https://example.test'),
      directory: directory,
    );
    addTearDown(() async {
      cache.dispose();
      await directory.delete(recursive: true);
    });
    final painter = SkinTexturePainter(cache);
    const base = MotifDesignLayer(
      id: 'motif',
      motif: SkinMotif.star,
      x: .5,
      y: .5,
      size: .2,
      rotation: 12,
      opacity: 1,
      color: '#ffffff',
      tint: false,
      placement: LayerPlacement.single,
    );

    expect(painter.layerPositions(base, 100, 50), hasLength(1));
    expect(
      painter.layerPositions(
        const MotifDesignLayer(
          id: 'corners',
          motif: SkinMotif.star,
          x: .5,
          y: .5,
          size: .2,
          rotation: 0,
          opacity: 1,
          color: '#ffffff',
          tint: false,
          placement: LayerPlacement.corners,
        ),
        100,
        50,
      ),
      hasLength(4),
    );
  });

  test('Nocturne produces board and piece textures at web sizes', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'skin-nocturne-test',
    );
    final cache = SkinImageCache(
      baseUri: Uri.parse('https://example.test'),
      directory: directory,
    );
    addTearDown(() async {
      cache.dispose();
      await directory.delete(recursive: true);
    });
    final Skin skin = builtinSkins.firstWhere((skin) => skin.id == 'nocturne');
    final SkinArtwork? artwork = await SkinTexturePainter(cache).paint(skin);
    if (artwork != null) addTearDown(artwork.dispose);

    expect(artwork, isNotNull);
    expect(artwork![SkinSurface.board].width, 1024);
    expect(artwork[SkinSurface.darkCap].height, 512);
    expect(artwork[SkinSurface.lightBody].height, 256);
    expect(artwork.metallicRoughness, isNotNull);
    expect(artwork.metallicRoughness!.width, 1024);
  });

  for (final String id in const ['pickmi', 'sakura-nocturne']) {
    test('$id produces every web surface at the expected size', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'skin-$id-test',
      );
      final cache = SkinImageCache(
        baseUri: Uri.parse('https://example.test'),
        directory: directory,
      );
      addTearDown(() async {
        cache.dispose();
        await directory.delete(recursive: true);
      });
      final Skin skin = builtinSkins.firstWhere((skin) => skin.id == id);
      final SkinArtwork? artwork = await SkinTexturePainter(cache)
          .paint(skin, preloadImages: false);
      if (artwork != null) addTearDown(artwork.dispose);

      expect(artwork, isNotNull);
      expect(artwork!.images, hasLength(SkinSurface.values.length));
      expect(artwork[SkinSurface.board].width, 1024);
      expect(artwork[SkinSurface.darkCap].height, 512);
      expect(artwork[SkinSurface.lightBody].height, 256);
    });
  }
}
