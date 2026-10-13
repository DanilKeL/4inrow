import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/appearance/domain/model/skin_catalog.dart';
import 'package:http/http.dart' as http;

final class AppearanceRepository {
  new({
    required this._baseUri,
    required this._preferences,
    http.Client? client,
    Future<bool> Function()? networkAvailable,
  }) : _client = client ?? http.Client(),
       _networkAvailable = networkAvailable ?? _hasNetworkInterface {
    _highestRevision = cached().revision;
  }

  static const String cacheKey = 'four-skins-v1';
  static const Duration reconnectDelay = Duration(seconds: 30);
  final Uri _baseUri;
  final PreferencesDatasourceTool _preferences;
  final http.Client _client;
  final Future<bool> Function() _networkAvailable;
  late int _highestRevision;

  SkinCatalog cached() {
    try {
      return SkinCatalog.decode(_preferences.getString(cacheKey) ?? '') ??
          defaultSkinCatalog();
    } on Object {
      return defaultSkinCatalog();
    }
  }

  Future<SkinCatalog?> refresh() async {
    try {
      if (!await _networkAvailable()) return null;
      final http.Response response = await _client
          .get(
            _baseUri.resolve('/appearance'),
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final SkinCatalog? catalog = SkinCatalog.decode(response.body);
      if (catalog == null || !await save(catalog)) return null;
      return catalog;
    } on Object {
      return null;
    }
  }

  Stream<SkinCatalog> events() async* {
    while (true) {
      if (!await _networkAvailable()) {
        await Future<void>.delayed(reconnectDelay);
        continue;
      }
      try {
        final request =
            http.Request('GET', _baseUri.resolve('/appearance/events'))
              ..headers.addAll(const {
                'Accept': 'text/event-stream',
                'Cache-Control': 'no-cache',
              });
        final http.StreamedResponse response = await _client
            .send(request)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200 ||
            !(response.headers['content-type'] ?? '').startsWith(
              'text/event-stream',
            )) {
          await response.stream.drain<void>();
          throw StateError('Appearance event stream unavailable');
        }
        String event = '';
        final data = StringBuffer();
        await for (final String line
            in response.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.isEmpty) {
            if ((event.isEmpty || event == 'skins') && data.isNotEmpty) {
              final SkinCatalog? catalog = SkinCatalog.decode(data.toString());
              if (catalog != null && await save(catalog)) {
                yield catalog;
              }
            }
            event = '';
            data.clear();
          } else if (line.startsWith('event:')) {
            event = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            if (data.isNotEmpty) data.writeln();
            data.write(line.substring(5).trimLeft());
          }
        }
        if ((event.isEmpty || event == 'skins') && data.isNotEmpty) {
          final SkinCatalog? catalog = SkinCatalog.decode(data.toString());
          if (catalog != null && await save(catalog)) yield catalog;
        }
      } on Object {
        // The cached appearance remains active during outages.
      }
      await Future<void>.delayed(reconnectDelay);
    }
  }

  Future<bool> save(SkinCatalog catalog) async {
    if (catalog.revision < _highestRevision) return false;
    _highestRevision = catalog.revision;
    await _preferences.setString(cacheKey, catalog.encode());
    return true;
  }

  void dispose() => _client.close();

  static Future<bool> _hasNetworkInterface() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list();
      return interfaces.any((interface) => interface.addresses.isNotEmpty);
    } on Object {
      // If the platform cannot report interfaces, let the HTTP timeout decide.
      return true;
    }
  }
}
