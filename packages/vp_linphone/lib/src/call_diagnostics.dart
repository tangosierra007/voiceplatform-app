import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/foundation.dart' show compute;

import 'log_scrubber.dart';

/// The contract's limit for `POST /app/v1/diagnostics/call-logs`.
const int callLogMaxBytes = 2 * 1024 * 1024;

/// First line of an export whose oldest part was cut to fit [callLogMaxBytes].
const String callLogTruncatedMarker = '[vp_linphone: earlier lines removed to keep this log under 2 MB]';

/// Gzips [text] (already scrubbed) to at most [maxBytes]. If it doesn't fit,
/// the oldest lines are dropped, at a line boundary, and
/// [callLogTruncatedMarker] goes first.
Uint8List packCallLog(String text, {int maxBytes = callLogMaxBytes}) {
  var packed = gzip.encode(utf8.encode(text));
  if (packed.length <= maxBytes) return Uint8List.fromList(packed);
  var keep = text.length;
  while (true) {
    keep = (keep * maxBytes / packed.length * 0.95).floor();
    if (keep <= 0) return Uint8List.fromList(gzip.encode(utf8.encode('$callLogTruncatedMarker\n')));
    var start = text.length - keep;
    final nl = text.indexOf('\n', start);
    if (nl >= 0 && nl + 1 < text.length) start = nl + 1;
    packed = gzip.encode(utf8.encode('$callLogTruncatedMarker\n${text.substring(start)}'));
    if (packed.length <= maxBytes) return Uint8List.fromList(packed);
  }
}

/// Scrubs [text] and packs it as [packCallLog] does, in a background isolate
/// (`compute`): a log can be megabytes, and neither the regexes nor gzip
/// belong on the UI isolate.
Future<Uint8List> scrubAndPackCallLog(String text, {int maxBytes = callLogMaxBytes}) =>
    compute(_scrubAndPack, (text, maxBytes));

Uint8List _scrubAndPack((String, int) args) => packCallLog(LogScrubber().scrub(args.$1), maxBytes: args.$2);

/// Posts a gzipped call log to `POST /app/v1/diagnostics/call-logs`
/// (Content-Type `application/gzip`) and returns the reference from the 201
/// answer, for example `LOG-7F3K9Q`. The app (4.4) passes its generated API
/// client's call, which adds the bearer token and `X-VP-App`.
typedef CallLogUploader = Future<String> Function(Uint8List gzippedLog);

/// No call has been logged on this device yet: nothing to send.
final class NoCallLog implements Exception {
  const NoCallLog();
  @override
  String toString() => 'No call log yet';
}

/// "Send call logs to support" for the Me screen (spec 22 Diagnostics,
/// decision 140; APP9). The log is the engine's last call, scrubbed on the
/// platform side as it was written, again on export, and again in Dart, then
/// gzipped to at most 2 MB. Nothing from the address book is ever in it
/// (APP12): the engine never sees it.
final class CallDiagnostics {
  CallDiagnostics({required this.engine, required this.upload});

  final CallEngine engine;
  final CallLogUploader upload;

  /// The gzipped log of the last call; empty when there is none.
  Future<Uint8List> lastCallLog() => engine.exportLastCallLog();

  /// Uploads [lastCallLog] and returns the reference to quote to support.
  /// Throws [NoCallLog] when there is nothing to send; upload errors (for
  /// example 413 `log_too_large`) come from [upload] as they are.
  Future<String> sendCallLogs() async {
    final log = await lastCallLog();
    if (log.isEmpty) throw const NoCallLog();
    return upload(log);
  }
}
