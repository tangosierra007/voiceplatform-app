import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/api.dart';

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

/// From `GET /me` for now; the `badges` event on the stream updates it in 4.3.
final shellStatusProvider = Provider<ShellStatus>((ref) {
  final me = ref.watch(meProvider).value;
  if (me == null) return const ShellStatus();
  return ShellStatus(
    recentsBadge: me.badges?.recents ?? 0,
    messagesBadge: me.badges?.messages ?? 0,
    hasSmsLine: me.permissions.messages,
  );
});
