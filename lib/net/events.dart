import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One Server-Sent Event from `GET /events` (contract: presence.snapshot,
/// presence, badges, reauth). [data] is the decoded JSON object.
@immutable
class ServerEvent {
  const ServerEvent(this.type, this.data, {this.id});
  final String type;
  final Map<String, Object?> data;
  final String? id;

  @override
  String toString() => 'ServerEvent($type)';
}

/// Parses an SSE text stream (lines already split) into events. Comment lines
/// (the 25 s heartbeat) are dropped; an event without `event:` is `message`.
class SseParser extends StreamTransformerBase<String, ServerEvent> {
  const SseParser();

  @override
  Stream<ServerEvent> bind(Stream<String> lines) async* {
    String? type;
    String? id;
    final data = <String>[];
    await for (final raw in lines) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          final decoded = jsonDecode(data.join('\n'));
          if (decoded is Map<String, Object?>) {
            yield ServerEvent(type ?? 'message', decoded, id: id);
          }
        }
        type = null;
        data.clear();
        continue;
      }
      if (line.startsWith(':')) continue;
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          type = value;
        case 'data':
          data.add(value);
        case 'id':
          id = value;
      }
    }
  }
}

/// Opens the event stream with the same Dio (so `X-VP-App` and the bearer are
/// on it). Foreground only: the caller cancels the subscription when the app
/// goes to the background.
Stream<ServerEvent> openEvents(Dio dio, {CancelToken? cancelToken}) async* {
  final res = await dio.get<ResponseBody>(
    '/events',
    cancelToken: cancelToken,
    options: Options(
      responseType: ResponseType.stream,
      headers: {'Accept': 'text/event-stream'},
      receiveTimeout: Duration.zero,
    ),
  );
  yield* res.data!.stream
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(const SseParser());
}
