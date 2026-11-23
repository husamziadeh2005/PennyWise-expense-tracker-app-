import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:expense_tracker/core/config/api_config.dart';

export 'package:expense_tracker/core/config/api_config.dart';

/// Error returned by the API (or a network problem).
/// [code] mirrors the API's `error.code` (e.g. `already_exists`).
class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'unknown', this.status = 0});

  final String message;
  final String code;
  final int status;

  bool get isNetwork => code == 'network_error' || code == 'timeout';

  @override
  String toString() => message;
}

/// Small HTTP client for the PennyWise API.
///
/// * Adds `Authorization: Bearer <Supabase access token>` to every call.
/// * Refreshes an expired token before sending, and once more if the API
///   still answers 401. If that fails the user is signed out (the
///   AuthGate then shows the login screen with a message).
/// * Turns every failure into an [ApiException] with a readable message.
class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  static const _timeout = Duration(seconds: 20);

  /// Replaceable in tests (e.g. with `MockClient` from package:http/testing).
  @visibleForTesting
  http.Client httpClient = http.Client();

  /// Replaceable in tests; normally reads the Supabase session.
  @visibleForTesting
  Future<String?> Function({bool forceRefresh})? tokenOverride;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  Future<dynamic> get(String path, {Map<String, String?>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path, {Map<String, String?>? query}) =>
      _send('DELETE', path, query: query);

  /// Uploads one file as multipart/form-data (field name "file").
  Future<dynamic> upload(String path, Uint8List bytes, String filename) =>
      _send('PUT', path, file: (bytes, filename));

  Future<String?> _token({bool forceRefresh = false}) async {
    if (tokenOverride != null) return tokenOverride!(forceRefresh: forceRefresh);
    var session = _auth.currentSession;
    if (session == null) return null;
    if (forceRefresh || session.isExpired) {
      try {
        session = (await _auth.refreshSession()).session;
      } on AuthException {
        return null;
      }
    }
    return session?.accessToken;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
    (Uint8List, String)? file,
  }) async {
    final cleanQuery = {
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}/api$path')
        .replace(queryParameters: cleanQuery.isEmpty ? null : cleanQuery);

    var response = await _attempt(method, uri, body, file, await _token());
    if (response.statusCode == 401) {
      // Token may have just expired: refresh once and retry.
      final fresh = await _token(forceRefresh: true);
      if (fresh != null) response = await _attempt(method, uri, body, file, fresh);
      if (response.statusCode == 401) {
        if (tokenOverride == null) await _auth.signOut(scope: SignOutScope.local).catchError((_) {});
        throw const ApiException('Your session has expired. Please log in again.',
            code: 'unauthorized', status: 401);
      }
    }
    return _decode(response);
  }

  Future<http.Response> _attempt(
    String method,
    Uri uri,
    Object? body,
    (Uint8List, String)? file,
    String? token,
  ) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      if (file != null) {
        final (bytes, filename) = file;
        final request = http.MultipartRequest(method, uri)
          ..headers.addAll(headers)
          ..files.add(http.MultipartFile.fromBytes('file', bytes,
              filename: filename, contentType: _mediaType(filename)));
        return await http.Response.fromStream(await httpClient.send(request).timeout(_timeout));
      }
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return await http.Response.fromStream(await httpClient.send(request).timeout(_timeout));
    } on TimeoutException {
      throw const ApiException('The server is taking too long. Please try again.',
          code: 'timeout');
    } on SocketException {
      throw const ApiException('Cannot reach the server. Check your connection and try again.',
          code: 'network_error');
    } on http.ClientException {
      throw const ApiException('Cannot reach the server. Check your connection and try again.',
          code: 'network_error');
    }
  }

  dynamic _decode(http.Response response) {
    dynamic json;
    try {
      json = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return json;

    final error = json is Map ? json['error'] : null;
    if (kDebugMode) debugPrint('API ${response.statusCode}: ${response.body}');
    throw ApiException(
      (error is Map ? error['message'] as String? : null) ?? _fallbackMessage(response.statusCode),
      code: (error is Map ? error['code'] as String? : null) ?? 'http_${response.statusCode}',
      status: response.statusCode,
    );
  }

  static String _fallbackMessage(int status) => switch (status) {
        404 => 'Not found.',
        413 => 'The file is too large.',
        429 => 'Too many requests. Please wait a moment.',
        >= 500 => 'The server had a problem. Please try again.',
        _ => 'Something went wrong. Please try again.',
      };

  static MediaType _mediaType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'heic' || 'heif' => MediaType('image', 'heic'),
      'pdf' => MediaType('application', 'pdf'),
      _ => MediaType('image', 'jpeg'),
    };
  }
}
