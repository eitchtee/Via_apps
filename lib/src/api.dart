import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, {this.retryAfter});

  final int status;
  final String code;
  final String message;
  final Duration? retryAfter;

  /// The device was removed or its token rotated: sign out.
  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Turns "via.example.com" or "https://via.example.com/" into "https://via.example.com".
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Thin client for the Via HTTP API (v1). See the server's docs/api.md.
class ViaApi {
  ViaApi(this.server, {this.token, http.Client? client}) : _client = client ?? http.Client();

  final String server;
  final String? token;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$server/v1$path').replace(queryParameters: query);

  Map<String, String> _headers({String? bearer, bool json = false}) => {
    if ((bearer ?? token) != null) 'Authorization': 'Bearer ${bearer ?? token}',
    if (json) 'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? bearer,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(_headers(bearer: bearer, json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(timeout),
    ).timeout(timeout);
    return _decode(response.statusCode, response.headers, response.body);
  }

  static dynamic _decode(int status, Map<String, String> headers, String body) {
    dynamic data;
    if (body.isNotEmpty) {
      try {
        data = jsonDecode(body);
      } on FormatException {
        data = null;
      }
    }
    if (status >= 200 && status < 300) return data;
    final error = data is Map ? data['error'] : null;
    final retry = int.tryParse(headers['retry-after'] ?? '');
    throw ApiException(
      status,
      error is Map ? '${error['code']}' : 'http_$status',
      error is Map ? '${error['message']}' : 'The server answered $status',
      retryAfter: retry == null ? null : Duration(seconds: retry),
    );
  }

  // --- setup ----------------------------------------------------------------------------

  Future<ServerInfo> info() async => ServerInfo.fromJson(await _send('GET', '/info'));

  /// Returns a session token.
  Future<String> login(String username, String password) async =>
      (await _send('POST', '/auth/login', body: {'username': username, 'password': password}))['token']
          as String;

  Future<void> logout(String session) async {
    try {
      await _send('POST', '/auth/logout', bearer: session);
    } catch (_) {}
  }

  /// Registers this device with a session token. Returns the device and its token.
  Future<(Device, String)> registerDevice(String session, String name, String type) async {
    final data = await _send('POST', '/devices', bearer: session, body: {'name': name, 'type': type});
    return (Device.fromJson(data['device']), data['token'] as String);
  }

  // --- this device ----------------------------------------------------------------------

  Future<Device> me() async => Device.fromJson(await _send('GET', '/devices/me'));

  Future<Device> renameMe(String name) async =>
      Device.fromJson(await _send('PATCH', '/devices/me', body: {'name': name}));

  Future<void> setPushProvider(String provider, {String? token}) =>
      _send('PUT', '/devices/me/push', body: {'provider': provider, 'token': ?token});

  Future<void> deleteDevice(String session, String id) => _send('DELETE', '/devices/$id', bearer: session);

  // --- targets --------------------------------------------------------------------------

  Future<List<Device>> devices() async => [
    for (final d in await _send('GET', '/devices') as List) Device.fromJson(d),
  ];

  Future<List<Contact>> contacts() async {
    try {
      final data = await _send('GET', '/contacts') as List;
      return [
        for (final c in data)
          if (c['status'] == 'accepted') Contact.fromJson(c),
      ];
    } on ApiException catch (e) {
      if (e.status == 404) return []; // server without contacts
      rethrow;
    }
  }

  // --- receiving ------------------------------------------------------------------------

  Future<InboxPage> inbox({String? after, int limit = 50}) async =>
      InboxPage.fromJson(await _send('GET', '/inbox', query: {'limit': '$limit', 'after': ?after}));

  Future<void> ack(String id) => _send('POST', '/inbox/$id/ack');

  Future<void> ackMany(List<String> ids) => _send('POST', '/inbox/ack', body: {'ids': ids});

  /// Downloads a file item into [part], resuming from its current size.
  /// Returns false if the file is gone (410).
  Future<bool> downloadFile(String id, File part) async {
    final have = await part.exists() ? await part.length() : 0;
    final request = http.Request('GET', _uri('/inbox/$id/file'))
      ..headers.addAll(_headers())
      ..headers.remove('Accept');
    if (have > 0) request.headers['Range'] = 'bytes=$have-';
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode == 410 || response.statusCode == 404) {
      await response.stream.drain<void>();
      return false;
    }
    if (response.statusCode == 416) {
      // Already complete (or the partial file is bogus: the hash check will tell).
      await response.stream.drain<void>();
      return true;
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      _decode(response.statusCode, response.headers, await response.stream.bytesToString());
    }
    final sink = part.openWrite(mode: response.statusCode == 206 ? FileMode.append : FileMode.write);
    try {
      await response.stream.timeout(const Duration(seconds: 60)).pipe(sink);
    } finally {
      await sink.close();
    }
    return true;
  }

  /// Opens `GET /v1/inbox/events`. The caller reads and closes the stream.
  Future<http.StreamedResponse> events(http.Client client) async {
    final request = http.Request('GET', _uri('/inbox/events'))
      ..headers.addAll(_headers())
      ..headers['Accept'] = 'text/event-stream';
    final response = await client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      _decode(response.statusCode, response.headers, await response.stream.bytesToString());
    }
    return response;
  }

  // --- sending --------------------------------------------------------------------------

  Future<void> sendLink(String url, List<String> to, {String? title}) =>
      _send('POST', '/pushes', body: {'kind': 'link', 'url': url, 'title': ?title, 'to': to});

  Future<void> sendNote(String body, List<String> to, {String? title}) =>
      _send('POST', '/pushes', body: {'kind': 'note', 'body': body, 'title': ?title, 'to': to});

  Future<void> sendFile(
    File file,
    String name,
    String mime,
    List<String> to, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();
    final request = http.StreamedRequest('POST', _uri('/pushes/file', {'filename': name, 'to': to.join(',')}))
      ..headers.addAll(_headers())
      ..headers['Content-Type'] = mime
      ..contentLength = total;
    var sent = 0;
    unawaited(
      file
          .openRead()
          .map((chunk) {
            sent += chunk.length;
            onProgress?.call(sent, total);
            return chunk;
          })
          .pipe(request.sink as StreamConsumer<List<int>>),
    );
    final response = await http.Response.fromStream(await _client.send(request));
    _decode(response.statusCode, response.headers, response.body);
  }

  void close() => _client.close();
}
