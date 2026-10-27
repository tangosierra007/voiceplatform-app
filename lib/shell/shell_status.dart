import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/api.dart';
import '../net/live_events.dart';

/// What the tab bar needs: the two badge counts and whether Messages shows.
@immutable
class ShellStatus {
  const ShellStatus({
    this.recentsBadge = 0,
    this.messagesBadge = 0,
    this.hasSmsLine = false,
  });

  /// New voicemail plus unseen missed calls.
  final int recentsBadge;

  /// Unread texts.
  final int messagesBadge;

  /// Messages is hidden when the user has no SMS line (`Me.permissions.messages`).
  final bool hasSmsLine;

  @override
  bool operator ==(Object other) =>
      other is ShellStatus &&
      other.recentsBadge == recentsBadge &&
      other.messagesBadge == messagesBadge &&
      other.hasSmsLine == hasSmsLine;

  @override
  int get hashCode => Object.hash(recentsBadge, messagesBadge, hasSmsLine);
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

/// From `GET /me`, then each `badges` event on the stream.
final shellStatusProvider = Provider<ShellStatus>((ref) {
  final me = ref.watch(meProvider).value;
  if (me == null) return const ShellStatus();
  final live = ref.watch(liveBadgesProvider);
  return ShellStatus(
    recentsBadge: live?.recents ?? me.badges?.recents ?? 0,
    messagesBadge: live?.messages ?? me.badges?.messages ?? 0,
    hasSmsLine: me.permissions.messages,
  );
});
