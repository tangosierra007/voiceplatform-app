import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One request the app made, with its body as text.
class SeenRequest {
  SeenRequest(this.method, this.path, this.uri, this.headers, this.body);
  final String method;

  /// Below the base, for example `/voicemail/messages/x/media-url`.
  final String path;
  final Uri uri;
  final Map<String, Object?> headers;
  final String body;

  @override
  String toString() => '$method $path';
}

/// Answers the app's requests in memory, by `METHOD /path` below `/app/v1`,
/// and keeps every request so a test can check what left the device.
class FakeApi implements HttpClientAdapter {
  FakeApi([Map<String, Object? Function(SeenRequest r)>? routes])
    : routes = {...?routes};

  final Map<String, Object? Function(SeenRequest r)> routes;
  final requests = <SeenRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final b in requestStream) {
        bytes.addAll(b);
      }
    }
    final path = options.uri.path.replaceFirst('/app/v1', '');
    final r = SeenRequest(options.method, path, options.uri, {
      ...options.headers,
    }, utf8.decode(bytes, allowMalformed: true));
    requests.add(r);
    final handler = routes['${options.method} $path'];
    if (handler == null) {
      return ResponseBody.fromString(
        '{"error":"not_found","message":"Not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final out = handler(r);
    if (out == null) return ResponseBody.fromString('', 204);
    if (out is (int, Object?)) {
      return ResponseBody.fromString(
        jsonEncode(out.$2),
        out.$1,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(out),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
