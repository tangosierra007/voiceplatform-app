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
    // Heard once it plays. If the server refuses, the counts are already
    // back to what it has, and the message stays new: the next play asks
    // again. Nothing to tell the person while it plays.
    if (!m.heard) {
      unawaited(markHeard(m, heard: true).catchError((Object _) {}));
    }
  }

  @visibleForTesting
  void debugLoad(String id) =>
      state = VoicemailPlayerState(loadedId: id, speaker: state.speaker);

  Future<void> setSpeaker(bool on) async {
    state = VoicemailPlayerState(loadedId: state.loadedId, speaker: on);
    await _player.setSpeaker(on);
  }

  Future<void> seek(Duration to) => _player.seek(to);

  /// Mark heard or new again. The Recents chip, the box counts and the tab
  /// badge move at once, then follow the server. Throws when the server
  /// refused it, after the counts are back to what the server has.
  Future<void> markHeard(VoicemailMessage m, {required bool heard}) => _counted(
    m,
    heard == m.heard ? 0 : (heard ? -1 : 1),
    () => ref
        .read(appApiProvider)
        .voicemail
        .postVoicemailMessagesIdRead(
          id: m.id,
          body: VoicemailMessagesIdReadRequestBody(heard: heard),
        ),
  );

  /// Delete [m]; a new one takes one off the counts at once. Throws when
  /// the server refused it (the counts are back as the server has them).
  Future<void> delete(VoicemailMessage m) async {
    if (state.loadedId == m.id) {
      await _player.stop();
      state = VoicemailPlayerState(speaker: state.speaker);
    }
    await _counted(
      m,
      m.heard ? 0 : -1,
      () => ref
          .read(appApiProvider)
          .voicemail
          .postVoicemailMessagesIdDelete(id: m.id),
    );
  }

  /// Applies [delta] to the new counts at once, sends [change], then reads
  /// every count again (history, boxes, messages, `/me`) and drops the
  /// local change: from then on the counts are the server's. Rethrows the
  /// server's refusal once that is done.
  Future<void> _counted(
    VoicemailMessage m,
    int delta,
    Future<void> Function() change,
  ) async {
    final pending = ref.read(voicemailPendingProvider.notifier);
    if (delta != 0) pending.add(m.id, m.boxId, delta);
    Object? failed;
    StackTrace? trace;
    try {
      await change();
      pending.ack(m.id);
    } catch (e, s) {
      failed = e;
      trace = s;
    }
    // What the reads below will include: this change and any other the
    // server took before them (two changes in flight).
    final upTo = pending.mark;
    ref.invalidate(voicemailBoxesProvider);
    ref.invalidate(voicemailMessagesProvider);
    for (final f in RecentsFilter.values) {
      ref.invalidate(historyProvider(f));
    }
    ref.invalidate(callsWithProvider);
    ref.read(liveBadgesProvider.notifier).forget();
    ref.invalidate(meProvider);
    await Future.wait<Object?>([
      for (final f in [
        ref.read(historyProvider(RecentsFilter.all).future),
        ref.read(voicemailBoxesProvider.future),
        ref.read(meProvider.future),
      ])
        f.then<Object?>((v) => v, onError: (_) => null),
    ]);
    pending
      ..settle(VoicemailCount.history, upTo: upTo)
      ..settle(VoicemailCount.boxes, upTo: upTo)
      ..remove(m.id);
    // (The API's own Error model hides dart:core's here.)
    if (failed != null) await Future<void>.error(failed, trace);
  }

  /// Leaving Recents stops playback.
  Future<void> stop() async {
    if (state.loadedId == null) return;
    await _player.stop();
    state = VoicemailPlayerState(speaker: state.speaker);
  }
}
