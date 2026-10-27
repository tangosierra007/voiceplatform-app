import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../net/api.dart';
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
  ref.invalidate(voicemailBoxesProvider);
  ref.invalidate(voicemailMessagesProvider);
}
