import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// False only when no `GET /me` has ever answered for this session (an
  /// app updated from a build that kept no tab set, still loading): the
  /// shell then leaves the current tab alone rather than bouncing it.
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

  /// The tabs to draw while [current] is open. The same as [tabs], except
  /// that while the tab set is unknown an open Messages (from a text
  /// notification) stays rather than bouncing to Keypad. A [current] not in
  /// the answer has gone for good: the shell moves to Keypad.
  List<AppTab> tabsWhileOn(AppTab current) => [
    for (final t in AppTab.values)
      if (t != AppTab.messages || hasSmsLine || (!tabsKnown && t == current)) t,
  ];

  /// Whether the Messages route may open (the router's redirect).
  bool get allowsMessages => hasSmsLine || !tabsKnown;

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

  /// Each answer from `GET /me`, and the sign-in session's `me`.
  void record(Me me) {
    final messages = me.permissions.messages;
    if (state.hasSmsLine != messages) {
      unawaited(
        ref.read(sharedPreferencesProvider).setBool(storageKey, messages),
      );
    }
    state = LastKnownShell(hasSmsLine: messages, badges: me.badges);
  }
}

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
    recentsBadge: live?.recents ?? badges?.recents ?? 0,
    messagesBadge: live?.messages ?? badges?.messages ?? 0,
    hasSmsLine: hasSmsLine ?? false,
    tabsKnown: hasSmsLine != null,
    meFailed: m == null && me.hasError,
  );
});
