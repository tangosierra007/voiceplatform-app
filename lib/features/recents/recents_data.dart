import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/numbers.dart';
import '../../net/api.dart';
import '../../shell/list_detail.dart';
import '../../shell/shell_status.dart';

/// The Recents filters (AppRecents): All, Missed, Voicemail, Mine only.
enum RecentsFilter { all, missed, voicemail, mine }

final recentsFilterProvider =
    NotifierProvider<RecentsFilterNotifier, RecentsFilter>(
      RecentsFilterNotifier.new,
    );

class RecentsFilterNotifier extends Notifier<RecentsFilter> {
  @override
  RecentsFilter build() => RecentsFilter.all;
  void set(RecentsFilter f) => state = f;
}

/// The call the person opened (by `HistoryEntry.id`): its own page on the
/// phone, beside the list at 800 dp and wider (FoldRecents). Kept across
/// fold and unfold.
final pickedRecentProvider = NotifierProvider<PickedNotifier, String?>(
  PickedNotifier.new,
);

/// One page of history for a filter (`GET /history`), newest first.
final historyProvider = FutureProvider.family<HistoryPage, RecentsFilter>((
  ref,
  f,
) async {
  if (ref.watch(accessTokenProvider) == null) {
    return const HistoryPage(
      items: [],
      counts: Counts(missed: 0, voicemail: 0),
    );
  }
  final api = ref.watch(appApiProvider);
  return api.history.getHistory(
    filter: switch (f) {
      RecentsFilter.missed => HistoryFilter.missed,
      RecentsFilter.voicemail => HistoryFilter.voicemail,
      _ => HistoryFilter.all,
    },
    mine: f == RecentsFilter.mine,
  );
});

/// "Calls with this number" for a call's detail (`GET /history?number=`),
/// newest first. The app keeps only the entries with this number itself
/// too, so a server that doesn't filter yet still gives the right list;
/// if the request fails, the calls Recents has loaded stand in.
final callsWithProvider = FutureProvider.family<List<HistoryEntry>, String>((
  ref,
  number,
) async {
  final digits = nationalDigits(number);
  bool same(HistoryEntry h) => nationalDigits(h.number) == digits;
  try {
    if (ref.watch(accessTokenProvider) == null) throw StateError('signed out');
    final page = await ref
        .watch(appApiProvider)
        .history
        .getHistory(number: number);
    return [...page.items.where(same)];
  } catch (_) {
    final all = await ref.watch(historyProvider(RecentsFilter.all).future);
    return [...all.items.where(same)];
  }
});

/// Opening Recents marks the missed calls seen up to now (`POST
/// /history/seen`), which clears that part of the tab badge.
Future<void> markHistorySeen(Ref ref) async {
  try {
    await ref
        .read(appApiProvider)
        .history
        .postHistorySeen(
          body: HistorySeenRequestBody(upTo: ref.read(clockProvider)().toUtc()),
        );
    ref.read(liveBadgesProvider.notifier).forget();
    ref.invalidate(meProvider);
  } catch (_) {
    // Next time.
  }
}

final markHistorySeenProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => markHistorySeen(ref),
);

/// Voicemail boxes the user may open: Mine and shared ones, with counts.
final voicemailBoxesProvider = FutureProvider<List<VoicemailBox>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return ref.watch(appApiProvider).voicemail.getVoicemailBoxes();
});

/// The box picked in the Voicemail filter; null is "All boxes".
final voicemailBoxProvider = NotifierProvider<VoicemailBoxNotifier, String?>(
  VoicemailBoxNotifier.new,
);

class VoicemailBoxNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final voicemailMessagesProvider =
    FutureProvider.family<List<VoicemailMessage>, String?>((ref, box) async {
      if (ref.watch(accessTokenProvider) == null) return const [];
      final page = await ref
          .watch(appApiProvider)
          .voicemail
          .getVoicemailMessages(boxId: box);
      return page.items;
    });

/// The message open with the player; null opens the newest.
final openVoicemailProvider = NotifierProvider<OpenVoicemailNotifier, String?>(
  OpenVoicemailNotifier.new,
);

class OpenVoicemailNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

/// Refreshes Recents and Voicemail after a change.
void refreshRecents(WidgetRef ref) {
  for (final f in RecentsFilter.values) {
    ref.invalidate(historyProvider(f));
  }
  ref.invalidate(callsWithProvider);
  ref.invalidate(voicemailBoxesProvider);
  ref.invalidate(voicemailMessagesProvider);
}
