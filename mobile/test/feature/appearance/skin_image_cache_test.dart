import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/appearance/data/skin_image_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List png;

  setUpAll(() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF3661EE), ui.BlendMode.src);
    final ui.Image image = await recorder.endRecording().toImage(1, 1);
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!;
    image.dispose();
    png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });

  test('valid hashed image is decoded and reused from memory', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'skin-cache-test',
    );
    var requests = 0;
    final id = sha256.convert(png).toString();
    final cache = SkinImageCache(
      baseUri: Uri.parse('https://example.test'),
      directory: directory,
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/appearance/assets/$id');
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    addTearDown(() async {
      cache.dispose();
      await directory.delete(recursive: true);
    });

    final ui.Image first = await cache.load(id);
    final ui.Image second = await cache.load(id);

    expect(first.width, 1);
    expect(identical(first, second), isTrue);
    expect(requests, 1);
  });

  test('wrong MIME and hash are rejected', () async {
    Future<void> expectRejected({
      required String id,
      required String mime,
    }) async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'skin-bad-test',
      );
      final cache = SkinImageCache(
        baseUri: Uri.parse('https://example.test'),
        directory: directory,
        client: MockClient(
          (_) async =>
              http.Response.bytes(png, 200, headers: {'content-type': mime}),
        ),
      );
      try {
        await expectLater(cache.load(id), throwsFormatException);
      } finally {
        cache.dispose();
        await directory.delete(recursive: true);
      }
    }

    await expectRejected(
      id: sha256.convert(png).toString(),
      mime: 'text/plain',
    );
    await expectRejected(
      id: '0000000000000000000000000000000000000000000000000000000000000000',
      mime: 'image/png',
    );
  });

  test('payloads above 512 KB are rejected before decoding', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'skin-large-test',
    );
    final bytes = Uint8List(SkinImageCache.maxBytes + 1);
    final cache = SkinImageCache(
      baseUri: Uri.parse('https://example.test'),
      directory: directory,
      client: MockClient(
        (_) async => http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );
    addTearDown(() async {
      cache.dispose();
      await directory.delete(recursive: true);
    });

    await expectLater(
      cache.load(sha256.convert(bytes).toString()),
      throwsFormatException,
    );
  });
}
