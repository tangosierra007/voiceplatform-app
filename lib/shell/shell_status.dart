import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/api.dart';
import '../net/live_events.dart';
import '../theme/theme_preference.dart';
import 'vp_tab_bar.dart';

/// What the tab bar (and, at 600 dp and wider, the navigation rail) needs:
/// which tabs show, the two badge counts, and whether `GET /me` is failing.
/// One rule for both: [tabs].
@immutable
class ShellStatus {
  const ShellStatus({
    this.recentsBadge = 0,
    this.messagesBadge = 0,
    this.hasSmsLine = false,
    this.tabsKnown = true,
    this.meFailed = false,
  });

  /// New voicemail plus unseen missed calls.
  final int recentsBadge;

  /// Unread texts.
  final int messagesBadge;

  /// Messages is hidden when the user has no SMS line (`Me.permissions.messages`),
  /// from the latest `GET /me`, or the last one known when it fails.
  final bool hasSmsLine;

  /// False when no answer from `GET /me` (or the sign-in session) has ever
  /// been kept: a fresh install whose `/me` fails, or a build updated from
  /// one that kept no tab set. Messages is then hidden and refused, and the
  /// failure banner says some tabs may be missing.
  final bool tabsKnown;

  /// `GET /me` failed and no answer from it is held in memory (for example
  /// a cold start with no network). The tabs and badges are the last known;
  /// Me shows its error state.
  final bool meFailed;

  /// The visible tabs, in [AppTab] order.
  List<AppTab> get tabs => [
    for (final t in AppTab.values)
      if (t != AppTab.messages || hasSmsLine) t,
  ];

  /// Whether the Messages route may open (the router's redirect): only with
  /// an SMS line, from `/me` or the last known tab set. Nothing known (still
  /// loading, or failed) refuses it, as it hides the tab.
  bool get allowsMessages => hasSmsLine;

  @override
  bool operator ==(Object other) =>
      other is ShellStatus &&
      other.recentsBadge == recentsBadge &&
      other.messagesBadge == messagesBadge &&
      other.hasSmsLine == hasSmsLine &&
      other.tabsKnown == tabsKnown &&
      other.meFailed == meFailed;

  @override
  int get hashCode =>
      Object.hash(recentsBadge, messagesBadge, hasSmsLine, tabsKnown, meFailed);
}

/// The latest `badges` event from the stream; null until one arrives, or
/// after [LiveBadgesNotifier.forget] when the app has changed what they count
/// (Recents seen, a voicemail heard) and `GET /me` is asked again.
final liveBadgesProvider = NotifierProvider<LiveBadgesNotifier, Badges?>(
  LiveBadgesNotifier.new,
);

class LiveBadgesNotifier extends Notifier<Badges?> {
  @override
  Badges? build() {
    final sub = ref.watch(liveEventsProvider).events.listen((e) {
      if (e.type != 'badges') return;
      try {
        state = Badges.fromJson(e.data);
      } catch (_) {
        // A malformed event leaves the last counts.
      }
    });
    ref.onDispose(sub.cancel);
    return null;
  }

  void forget() => state = null;
}

/// The last tab set and badges an answer from `GET /me` (or the sign-in
/// session's `me`) gave.
@immutable
class LastKnownShell {
  const LastKnownShell({this.hasSmsLine, this.badges});

  /// Null when nothing is known yet.
  final bool? hasSmsLine;

  /// In memory only: after a restart the counts come from `/me` or the stream.
  final Badges? badges;
}

/// Kept with the session: whether Messages shows is stored as one boolean
/// in shared preferences, which sign-out clears with everything else
/// (`localDataWipersProvider`). Nothing personal is stored: no name, number,
/// count or line. Badge counts are kept in memory only.
final lastKnownShellProvider =
    NotifierProvider<LastKnownShellNotifier, LastKnownShell>(
      LastKnownShellNotifier.new,
    );

class LastKnownShellNotifier extends Notifier<LastKnownShell> {
  static const storageKey = 'vp.shell.messagesTab';

  @override
  LastKnownShell build() => LastKnownShell(
    hasSmsLine: ref.read(sharedPreferencesProvider).getBool(storageKey),
  );

  /// Each answer from `GET /me`, and the sign-in session's `me`. A no-op
  /// without an access token (signed out, or signing out: see
  /// `AuthController.signOutLocally`), so a late answer never writes the
  /// tab set back after sign-out.
  void record(Me me) {
    if (ref.read(accessTokenProvider) == null) return;
    final messages = me.permissions.messages;
    if (state.hasSmsLine != messages) {
      unawaited(
        ref.read(sharedPreferencesProvider).setBool(storageKey, messages),
      );
    }
    state = LastKnownShell(hasSmsLine: messages, badges: me.badges);
  }
}

/// The new voicemail counts the server sends: the Recents tab badge (`/me`
/// and the stream's `badges`), the Recents chip (`GET /history`'s counts)
/// and the boxes' new counts.
enum VoicemailCount { badge, history, boxes }

/// One change made on this phone: its box, how it moves the new count, and
/// once the server has it ([ack]), which counts already show it.
@immutable
class PendingVoicemail {
  const PendingVoicemail(
    this.boxId,
    this.delta, {
    this.ack,
    this.settled = const {},
  });

  final String boxId;
  final int delta;

  /// When the server took the change (an order, not a time); null before.
  final int? ack;

  /// The counts read since then, which already include it.
  final Set<VoicemailCount> settled;

  PendingVoicemail copyWith({int? ack, Set<VoicemailCount>? settled}) =>
      PendingVoicemail(
        boxId,
        delta,
        ack: ack ?? this.ack,
        settled: settled ?? this.settled,
      );
}

/// Voicemail changes made on this phone (heard, new again, deleted) that the
/// server's counts don't show yet, by message. The Recents chip, the box
/// counts and the tab badge add them at once. Once the server has a change,
/// each count drops it as soon as a newer server figure for that count
/// arrives (a `badges` event, `/me`, history or the boxes read again), so
/// nothing is counted twice; the change itself goes when its own re-read is
/// done.
final voicemailPendingProvider =
    NotifierProvider<VoicemailPendingNotifier, Map<String, PendingVoicemail>>(
      VoicemailPendingNotifier.new,
    );

class VoicemailPendingNotifier extends Notifier<Map<String, PendingVoicemail>> {
  int _order = 0;

  @override
  Map<String, PendingVoicemail> build() {
    // A newer badge from the server already counts every change it took.
    ref.listen(liveBadgesProvider, (_, b) {
      if (b != null) settle(VoicemailCount.badge);
    });
    ref.listen(meProvider, (_, me) {
      if (me.hasValue && !me.isLoading) settle(VoicemailCount.badge);
    });
    return const {};
  }

  void add(String messageId, String boxId, int delta) =>
      state = {...state, messageId: PendingVoicemail(boxId, delta)};

  /// The server has the change to [messageId]: counts read after this
  /// include it.
  void ack(String messageId) {
    final p = state[messageId];
    if (p == null) return;
    state = {...state, messageId: p.copyWith(ack: ++_order)};
  }

  /// Now, in [ack]'s order: what a read starting now will include.
  int get mark => _order;

  /// A newer [count] arrived from the server: every change it took by
  /// [upTo] (by default, all it has taken) is in that count now.
  void settle(VoicemailCount count, {int? upTo}) {
    final limit = upTo ?? _order;
    var changed = false;
    final next = {
      for (final MapEntry(:key, :value) in state.entries)
        key:
            value.ack != null &&
                value.ack! <= limit &&
                !value.settled.contains(count)
            ? (() {
                changed = true;
                return value.copyWith(settled: {...value.settled, count});
              })()
            : value,
    };
    if (changed) state = next;
  }

  void remove(String messageId) => state = {...state}..remove(messageId);
}

extension VoicemailPending on Map<String, PendingVoicemail> {
  /// The change still to add to [count], all boxes.
  int total(VoicemailCount count) => values
      .where((v) => !v.settled.contains(count))
      .fold(0, (n, v) => n + v.delta);

  /// The change still to add to one box's new count.
  int forBox(String boxId) => values
      .where(
        (v) => v.boxId == boxId && !v.settled.contains(VoicemailCount.boxes),
      )
      .fold(0, (n, v) => n + v.delta);
}

/// [server] moved by [delta], never below none.
int withPending(int server, int delta) =>
    server + delta < 0 ? 0 : server + delta;

/// From `GET /me`, then each `badges` event on the stream. While `/me` loads
/// or fails, the last known tab set and badges stay: Messages never drops
/// out because a request failed.
final shellStatusProvider = Provider<ShellStatus>((ref) {
  final me = ref.watch(meProvider);
  final known = ref.watch(lastKnownShellProvider);
  final live = ref.watch(liveBadgesProvider);
  // Riverpod keeps the previous answer while reloading and after an error.
  final m = me.value;
  final badges = m?.badges ?? known.badges;
  final hasSmsLine = m?.permissions.messages ?? known.hasSmsLine;
  return ShellStatus(
    recentsBadge: withPending(
      live?.recents ?? badges?.recents ?? 0,
      ref.watch(voicemailPendingProvider).total(VoicemailCount.badge),
    ),
    messagesBadge: live?.messages ?? badges?.messages ?? 0,
    hasSmsLine: hasSmsLine ?? false,
    tabsKnown: hasSmsLine != null,
    meFailed: m == null && me.hasError,
  );
});

/// Back in the foreground with `GET /me` still failed: ask again. The shell
/// watches it while signed in; with the offline listener and Riverpod's own
/// retries, a failure never stays for good.
final meRetryOnResumeProvider = Provider<void>((ref) {
  final listener = AppLifecycleListener(
    onResume: () {
      if (ref.read(shellStatusProvider).meFailed) ref.invalidate(meProvider);
    },
  );
  ref.onDispose(listener.dispose);
});
