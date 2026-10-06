import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

enum RestClientFailure { network, invalidResponse, wrongType, server }

final class RestClientException implements Exception {
  const new(
    this.message, {
    this.failure = RestClientFailure.server,
    this.statusCode,
    this.data,
  });

  final String message;
  final RestClientFailure failure;
  final int? statusCode;
  final Map<String, dynamic>? data;

  @override
  String toString() => message;
}

final class SessionCookieStorage {
  const new(this._secureStorage);

  static const _key = 'four_session';
  final FlutterSecureStorage _secureStorage;

  Future<String?> read() => _secureStorage.read(key: _key);

  Future<void> write(String? cookie) => cookie == null
      ? _secureStorage.delete(key: _key)
      : _secureStorage.write(key: _key, value: cookie);
}

abstract interface class RestClient {
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  });

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?>? data,
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  });

  void dispose();
}

final class RestClient$Http implements RestClient {
  new({
    required String baseUrl,
    required this._cookieStorage,
    http.Client? client,
  }) : _baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  final Uri _baseUri;
  final SessionCookieStorage _cookieStorage;
  final http.Client _client;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  }) => _send(
    method: 'GET',
    path: path,
    queryParams: queryParams,
    headers: headers,
  );

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?>? data,
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  }) => _send(
    method: 'POST',
    path: path,
    data: data ?? const <String, Object?>{},
    queryParams: queryParams,
    headers: headers,
  );

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    Map<String, Object?>? data,
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  }) async {
    final String? cookie = await _cookieStorage.read();
    final Map<String, String> requestHeaders = <String, String>{
      'Accept': 'application/json',
      ...?headers,
      if (data != null) 'Content-Type': 'application/json',
      'Cookie': ?cookie,
    };
    final Uri uri = _baseUri
        .resolve(path)
        .replace(
          queryParameters: queryParams == null
              ? null
              : <String, String>{
                  for (final MapEntry<String, String?> entry
                      in queryParams.entries)
                    if (entry.value != null) entry.key: entry.value!,
                },
        );
    late final http.Response response;
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(requestHeaders)
        ..body = data == null ? '' : jsonEncode(data);
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 8));
    } on Object {
      throw const RestClientException('', failure: RestClientFailure.network);
    }
    await _captureCookie(response.headers['set-cookie']);
    final Object? body;
    try {
      body = response.body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      throw RestClientException(
        '',
        failure: RestClientFailure.invalidResponse,
        statusCode: response.statusCode,
      );
    }
    if (body is! Map<String, dynamic>) {
      throw RestClientException(
        '',
        failure: RestClientFailure.wrongType,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RestClientException(
        body['error']?.toString() ?? '',
        statusCode: response.statusCode,
        data: body,
      );
    }
    return body;
  }

  Future<void> _captureCookie(String? setCookie) async {
    if (setCookie == null) return;
    final RegExpMatch? match = RegExp(r'(four_session=[^;,\s]*)')
        .firstMatch(setCookie);
    if (match == null) return;
    final String cookie = match.group(1)!;
    await _cookieStorage.write(cookie.endsWith('=') ? null : cookie);
  }

  @override
  void dispose() => _client.close();
}
