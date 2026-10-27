import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../net/api.dart';

/// The longest greeting the platform takes (contract: up to 2 minutes, 5 MB).
const greetingLimit = Duration(minutes: 2);

/// My three greetings: when I can't answer, when I'm busy, and my name.
final greetingsProvider = FutureProvider<List<Greeting>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return ref.watch(appApiProvider).voicemail.getVoicemailGreetings();
});

/// Records a greeting to a file in the app's cache, as AAC in an M4A
/// container (`audio/mp4`), mono speech quality.
abstract interface class GreetingRecorder {
  Future<void> start();

  /// Stops and returns the file, or null if nothing was recorded.
  Future<File?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class DeviceGreetingRecorder implements GreetingRecorder {
  final _rec = AudioRecorder();
  String? _path;

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/greeting-'
        '${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 48000,
      ),
      path: _path!,
    );
  }

  @override
  Future<File?> stop() async {
    final p = await _rec.stop();
    return p == null ? null : File(p);
  }

  @override
  Future<void> cancel() async {
    await _rec.cancel();
    _path = null;
  }

  @override
  Future<void> dispose() => _rec.dispose();
}

final greetingRecorderProvider = Provider.autoDispose<GreetingRecorder>((ref) {
  final r = DeviceGreetingRecorder();
  ref.onDispose(r.dispose);
  return r;
});

/// Uploads a recording as the greeting of [kind] (`PUT
/// /voicemail/greetings/{kind}`, `audio/mp4`), then deletes the local file.
typedef GreetingUpload = Future<Greeting> Function(GreetingKind kind, File f);

final greetingUploadProvider = Provider<GreetingUpload>((ref) {
  return (kind, file) async {
    try {
      final bytes = await file.readAsBytes();
      final r = await ref
          .read(dioProvider)
          .put<Map<String, Object?>>(
            '/voicemail/greetings/${kind.json}',
            data: Stream.fromIterable([bytes]),
            options: Options(
              contentType: 'audio/mp4',
              headers: {Headers.contentLengthHeader: bytes.length},
            ),
          );
      return Greeting.fromJson(r.data!);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  };
});
