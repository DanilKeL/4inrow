import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

final class SkinImageCache {
  new({
    required this._baseUri,
    required Directory directory,
    http.Client? client,
  }) : _directory = Directory('${directory.path}/skin-assets-v1'),
       _client = client ?? http.Client();

  static const int maxBytes = 512 * 1024;
  static const int maxDimension = 1024;
  static const int maxFiles = 128;
  static const int maxDecoded = 16;
  static final RegExp _idPattern = RegExp(r'^[a-f0-9]{64}$');

  final Uri _baseUri;
  final Directory _directory;
  final http.Client _client;
  final LinkedHashMap<String, ui.Image> _images = LinkedHashMap();
  final Map<String, Future<ui.Image>> _pending = {};
  final Queue<Completer<void>> _queue = Queue();
  Future<void>? _initialTrim;
  int _active = 0;

  ui.Image? loaded(String id) {
    final ui.Image? image = _images.remove(id);
    if (image != null) _images[id] = image;
    return image;
  }

  Future<ui.Image> load(String id) {
    if (!_idPattern.hasMatch(id)) {
      return Future<ui.Image>.error(
        const FormatException('Invalid skin image id'),
      );
    }
    final ui.Image? cached = loaded(id);
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(
      id,
      () => _limited(() => _decode(id)).whenComplete(() {
        _pending.remove(id);
      }),
    );
  }

  Future<void> preload(Iterable<String> ids) async {
    await Future.wait<void>(
      ids.toSet().map((id) async {
        try {
          await load(id);
        } on Object {
          // Missing artwork must not make the palette unusable.
        }
      }),
    );
  }

  Future<T> _limited<T>(Future<T> Function() action) async {
    if (_active >= 4) {
      final gate = Completer<void>();
      _queue.add(gate);
      await gate.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_queue.isNotEmpty) _queue.removeFirst().complete();
    }
  }

  Future<ui.Image> _decode(String id) async {
    await _directory.create(recursive: true);
    try {
      await (_initialTrim ??= _trimDiskCache());
    } on Object {
      // The memory cache and network remain available on read-only storage.
    }
    final file = File('${_directory.path}/$id');
    Uint8List? bytes;
    if (await file.exists()) {
      try {
        final Uint8List stored = await file.readAsBytes();
        if (_validHash(id, stored) &&
            stored.isNotEmpty &&
            stored.length <= maxBytes) {
          bytes = stored;
          try {
            await file.setLastModified(DateTime.now());
          } on Object {
            // A read-only cache entry is still valid for offline rendering.
          }
        } else {
          await file.delete();
        }
      } on Object {
        bytes = null;
      }
    }
    if (bytes == null) {
      final request = http.Request(
        'GET',
        _baseUri.resolve('/appearance/assets/$id'),
      )..followRedirects = false;
      final http.StreamedResponse response = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final String? mime = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode != 200 ||
          !const {'image/png', 'image/jpeg', 'image/webp'}.contains(mime) ||
          (response.contentLength ?? 0) > maxBytes) {
        throw const FormatException('Invalid skin image');
      }
      final builder = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.stream.timeout(
        const Duration(seconds: 12),
      )) {
        if (builder.length + chunk.length > maxBytes) {
          throw const FormatException('Invalid skin image size');
        }
        builder.add(chunk);
      }
      final Uint8List downloaded = builder.takeBytes();
      if (downloaded.isEmpty || !_validHash(id, downloaded)) {
        throw const FormatException('Invalid skin image hash');
      }
      bytes = downloaded;
      try {
        await file.writeAsBytes(bytes, flush: true);
        await _trimDiskCache();
      } on Object {
        // Disk caching is optional.
      }
    }
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      if (image.width < 1 ||
          image.height < 1 ||
          image.width > maxDimension ||
          image.height > maxDimension) {
        image.dispose();
        try {
          if (await file.exists()) await file.delete();
        } on Object {
          // The invalid entry will be rejected again by its dimensions.
        }
        throw const FormatException('Invalid skin image dimensions');
      }
      _images[id] = image;
      while (_images.length > maxDecoded) {
        _images.remove(_images.keys.first)?.dispose();
      }
      return image;
    } on Object {
      try {
        if (await file.exists()) await file.delete();
      } on Object {
        // Disk cache cleanup is best effort.
      }
      rethrow;
    } finally {
      codec?.dispose();
    }
  }

  bool _validHash(String id, List<int> bytes) =>
      sha256.convert(bytes).toString() == id;

  Future<void> _trimDiskCache() async {
    final List<File> files = await _directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    if (files.length <= maxFiles) return;
    final dated = <({File file, DateTime date})>[];
    for (final file in files) {
      try {
        dated.add((file: file, date: await file.lastModified()));
      } on Object {
        dated.add((file: file, date: DateTime.fromMillisecondsSinceEpoch(0)));
      }
    }
    dated.sort((a, b) => a.date.compareTo(b.date));
    for (final ({DateTime date, File file}) entry in dated.take(
      dated.length - maxFiles,
    )) {
      try {
        await entry.file.delete();
      } on Object {
        // Best-effort eviction.
      }
    }
  }

  void dispose() {
    _client.close();
    for (final ui.Image image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}
