import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../net/api.dart';

/// Where playback is and whether it plays.
@immutable
class PlaybackState {
  const PlaybackState({
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration,
    this.failed = false,
  });
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration? duration;
  final bool failed;

  PlaybackState copyWith({
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
    bool? failed,
  }) => PlaybackState(
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    failed: failed ?? this.failed,
  );
}

/// Plays a voicemail or recording by streaming its signed URL (APP8). Nothing
/// is written to the device: no caching source, no download, and the URL is
/// asked for afresh each time (it lasts 5 minutes).
abstract interface class MediaPlayer {
  Stream<PlaybackState> get states;
  PlaybackState get state;

  /// Streams [url] with [headers]. Replaces whatever was loaded.
  Future<void> open(Uri url, Map<String, String> headers);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);

  /// Loudspeaker (true) or earpiece.
  Future<void> setSpeaker(bool on);
  Future<void> stop();
  Future<void> dispose();
}

/// The source the player streams from: a plain progressive URI source. Never
/// `LockCachingAudioSource`, which would keep the audio in a cache file
/// (APP8; `test/player_no_cache_test.dart` holds this).
AudioSource streamingSource(Uri url, Map<String, String> headers) =>
    ProgressiveAudioSource(url, headers: headers);

/// The URL to stream and the headers it needs. The contract's signed URL is
/// `/app/v1/media/<token>` on the API's origin and needs the bearer as well;
/// an absolute URL on another host gets no credentials.
(Uri, Map<String, String>) mediaRequest(
  String signedUrl,
  ApiConfig config,
  String? accessToken,
) {
  final base = Uri.parse(config.baseUrl);
  final url = base.resolve(signedUrl);
  final sameOrigin =
      url.scheme == base.scheme &&
      url.host == base.host &&
      url.port == base.port;
  return (
    url,
    {
      'X-VP-App': config.appHeader,
      if (sameOrigin && accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    },
  );
}

class JustAudioMediaPlayer implements MediaPlayer {
  JustAudioMediaPlayer()
    // Headers go straight to ExoPlayer and AVPlayer rather than through
    // just_audio's local proxy: one less copy of the stream on the device.
    : _player = AudioPlayer(useProxyForRequestHeaders: false) {
    _subs.addAll([
      _player.playerStateStream.listen((s) {
        final done = s.processingState == ProcessingState.completed;
        _set(
          _state.copyWith(
            playing: s.playing && !done,
            loading:
                s.processingState == ProcessingState.loading ||
                s.processingState == ProcessingState.buffering,
          ),
        );
        if (done) {
          unawaited(_player.pause());
          unawaited(_player.seek(Duration.zero));
        }
      }),
      _player.positionStream.listen((p) => _set(_state.copyWith(position: p))),
      _player.durationStream.listen((d) => _set(_state.copyWith(duration: d))),
    ]);
  }

  final AudioPlayer _player;
  final _subs = <StreamSubscription<Object?>>[];
  final _out = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  void _set(PlaybackState s) {
    _state = s;
    if (!_out.isClosed) _out.add(s);
  }

  @override
  Stream<PlaybackState> get states => _out.stream;

  @override
  PlaybackState get state => _state;

  @override
  Future<void> open(Uri url, Map<String, String> headers) async {
    _set(const PlaybackState(loading: true));
    try {
      await _player.setAudioSource(streamingSource(url, headers));
    } catch (_) {
      _set(const PlaybackState(failed: true));
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  bool _earpiece = false;

  /// Earpiece: voice-call attributes in communication mode with the
  /// loudspeaker off, as a phone plays voicemail held to the ear. Speaker:
  /// ordinary media playback. Only while nothing else holds the call audio.
  @override
  Future<void> setSpeaker(bool on) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final am = AndroidAudioManager();
    await _player.setAndroidAudioAttributes(
      AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: on
            ? AndroidAudioUsage.media
            : AndroidAudioUsage.voiceCommunication,
      ),
    );
    await am.setMode(
      on
          ? AndroidAudioHardwareMode.normal
          : AndroidAudioHardwareMode.inCommunication,
    );
    await am.setSpeakerphoneOn(on);
    _earpiece = !on;
  }

  Future<void> _restoreAudio() async {
    if (!_earpiece) return;
    _earpiece = false;
    try {
      await AndroidAudioManager().setMode(AndroidAudioHardwareMode.normal);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _restoreAudio();
    _set(const PlaybackState());
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _restoreAudio();
    await _out.close();
  }
}

/// One player for Recents (voicemail) and Me (recordings), made on first use.
final mediaPlayerProvider = Provider<MediaPlayer>((ref) {
  final p = JustAudioMediaPlayer();
  ref.onDispose(p.dispose);
  return p;
});

/// Who has the shared player loaded: `voicemail:<id>`, `recording:<id>`,
/// `greeting:<kind>`, or null. Each screen shows its controls as loaded only
/// while it is the owner, so opening one elsewhere resets the others.
final mediaOwnerProvider = NotifierProvider<MediaOwnerNotifier, String?>(
  MediaOwnerNotifier.new,
);

class MediaOwnerNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? owner) => state = owner;
  String? get owner => state;
}

final playbackProvider = StreamProvider<PlaybackState>((ref) {
  final p = ref.watch(mediaPlayerProvider);
  return p.states;
});
