import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../net/api.dart';
import '../../shell/shell_status.dart';
import 'media_player.dart';
import 'recents_data.dart';

/// What the voicemail player card is doing: which message is loaded, and
/// whether the loudspeaker is on.
class VoicemailPlayerState {
  const VoicemailPlayerState({this.loadedId, this.speaker = false});
  final String? loadedId;
  final bool speaker;
}

final voicemailPlayerProvider =
    NotifierProvider<VoicemailPlayerNotifier, VoicemailPlayerState>(
      VoicemailPlayerNotifier.new,
    );

class VoicemailPlayerNotifier extends Notifier<VoicemailPlayerState> {
  @override
  VoicemailPlayerState build() {
    // Another screen (Recordings, Greeting) took the player: the card is no
    // longer loaded.
    ref.listen<String?>(mediaOwnerProvider, (_, owner) {
      if (state.loadedId != null && owner != 'voicemail:${state.loadedId}') {
        state = VoicemailPlayerState(speaker: state.speaker);
      }
    });
    return const VoicemailPlayerState();
  }

  MediaPlayer get _player => ref.read(mediaPlayerProvider);

  /// Play or pause [m]. A fresh signed URL each time it is loaded: the URL
  /// lasts 5 minutes and the audio is streamed, never kept (APP8).
  Future<void> toggle(VoicemailMessage m) async {
    final p = _player;
    if (state.loadedId == m.id &&
        ref.read(mediaOwnerProvider) == 'voicemail:${m.id}' &&
        !p.state.failed) {
      if (p.state.playing) return p.pause();
      return p.play();
    }
    final api = ref.read(appApiProvider);
    final signed = await api.voicemail.postVoicemailMessagesIdMediaUrl(
      id: m.id,
    );
    final (url, headers) = mediaRequest(
      signed.url,
      ref.read(apiConfigProvider),
      ref.read(accessTokenProvider),
    );
    await p.open(url, headers);
    ref.read(mediaOwnerProvider.notifier).set('voicemail:${m.id}');
    state = VoicemailPlayerState(loadedId: m.id, speaker: state.speaker);
    await p.setSpeaker(state.speaker);
    unawaited(p.play());
    // Heard once it plays; a failure here leaves it new for next time.
    if (!m.heard) unawaited(markHeard(m, heard: true).catchError((_) {}));
  }

  @visibleForTesting
  void debugLoad(String id) =>
      state = VoicemailPlayerState(loadedId: id, speaker: state.speaker);

  Future<void> setSpeaker(bool on) async {
    state = VoicemailPlayerState(loadedId: state.loadedId, speaker: on);
    await _player.setSpeaker(on);
  }

  Future<void> seek(Duration to) => _player.seek(to);

  /// Mark heard or new again; the badge and the box counts follow.
  Future<void> markHeard(VoicemailMessage m, {required bool heard}) async {
    await ref
        .read(appApiProvider)
        .voicemail
        .postVoicemailMessagesIdRead(
          id: m.id,
          body: VoicemailMessagesIdReadRequestBody(heard: heard),
        );
    ref.invalidate(voicemailBoxesProvider);
    ref.invalidate(voicemailMessagesProvider);
    ref.read(liveBadgesProvider.notifier).forget();
    ref.invalidate(meProvider);
  }

  Future<void> delete(VoicemailMessage m) async {
    if (state.loadedId == m.id) {
      await _player.stop();
      state = VoicemailPlayerState(speaker: state.speaker);
    }
    await ref
        .read(appApiProvider)
        .voicemail
        .postVoicemailMessagesIdDelete(id: m.id);
    ref.invalidate(voicemailBoxesProvider);
    ref.invalidate(voicemailMessagesProvider);
    for (final f in RecentsFilter.values) {
      ref.invalidate(historyProvider(f));
    }
    ref.invalidate(meProvider);
  }

  /// Leaving Recents stops playback.
  Future<void> stop() async {
    if (state.loadedId == null) return;
    await _player.stop();
    state = VoicemailPlayerState(speaker: state.speaker);
  }
}
