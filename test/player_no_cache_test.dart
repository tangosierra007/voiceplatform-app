// APP8: voicemail and recordings are streamed from a short-lived signed URL
// and never kept on the device: no caching source, no download, no copy in
// the app's files, and a fresh URL each time a message is loaded.
// ignore_for_file: experimental_member_use
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:voiceplatform_app/features/recents/media_player.dart';
import 'package:voiceplatform_app/net/api.dart';

const _config = ApiConfig(
  baseUrl: 'https://api.example.test/app/v1',
  platform: 'android',
  appVersion: '1.0.0',
);

void main() {
  test('the source streams the URL; it is not a caching source', () {
    final s = streamingSource(
      Uri.parse('https://api.example.test/app/v1/media/t'),
      const {'Authorization': 'Bearer x'},
    );
    expect(s, isA<ProgressiveAudioSource>());
    expect(s, isNot(isA<LockCachingAudioSource>()));
    // A StreamAudioSource is fed from Dart, which is how a cache file or a
    // downloaded copy would get in.
    expect(s, isNot(isA<StreamAudioSource>()));
    expect((s as UriAudioSource).uri.scheme, 'https');
  });

  test('the contract URL resolves on the API origin with the bearer', () {
    final (url, headers) = mediaRequest('/app/v1/media/abc', _config, 'tok');
    expect(url.toString(), 'https://api.example.test/app/v1/media/abc');
    expect(headers['Authorization'], 'Bearer tok');
    expect(headers['X-VP-App'], 'android/1.0.0');
  });

  test('another host never gets the bearer', () {
    final (url, headers) = mediaRequest(
      'https://cdn.example.test/v/abc?sig=1',
      _config,
      'tok',
    );
    expect(url.host, 'cdn.example.test');
    expect(headers.containsKey('Authorization'), isFalse);
  });

  test('nothing in the app caches or saves played audio', () {
    final banned = [
      'LockCachingAudioSource',
      'AudioSource.file',
      'setFilePath',
      'getApplicationDocumentsDirectory',
      'getDownloadsDirectory',
      'getExternalStorageDirectory',
    ];
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        for (final b in banned) {
          if (line.contains(b)) hits.add('${f.path}:${i + 1} $b');
        }
      }
    }
    expect(hits, isEmpty);
  });
}
