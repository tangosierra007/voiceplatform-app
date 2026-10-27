import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../net/api.dart';
import '../../shell/shell_status.dart';

/// The SMS lines this user may text from (`GET /messages/lines`).
final smsLinesProvider = FutureProvider<List<SmsLine>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return ref.watch(appApiProvider).messages.getMessagesLines();
});

/// The line chip picked on Messages; null is All.
final messagesLineProvider = NotifierProvider<MessagesLineNotifier, String?>(
  MessagesLineNotifier.new,
);

class MessagesLineNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final threadsProvider = FutureProvider.family<ThreadPage, String?>((
  ref,
  lineId,
) async {
  if (ref.watch(accessTokenProvider) == null) {
    return const ThreadPage(items: [], unreadTotal: 0);
  }
  return ref.watch(appApiProvider).messages.getMessagesThreads(lineId: lineId);
});

/// A thread's messages, oldest first for the screen.
final threadMessagesProvider = FutureProvider.family<List<Message>, String>((
  ref,
  threadId,
) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  final page = await ref
      .watch(appApiProvider)
      .messages
      .getMessagesThreadsIdMessages(id: threadId);
  final items = [...page.items]..sort((a, b) => a.at.compareTo(b.at));
  return items;
});

/// After a `message` push, a send or a read: lists, the thread, the badge.
void refreshMessages(Ref ref) {
  ref.invalidate(threadsProvider);
  ref.invalidate(threadMessagesProvider);
  ref.read(liveBadgesProvider.notifier).forget();
  ref.invalidate(meProvider);
}

final messageActionsProvider = Provider<MessageActions>(MessageActions.new);

class MessageActions {
  MessageActions(this._ref);
  final Ref _ref;

  Future<void> markRead(String threadId) async {
    try {
      await _ref
          .read(appApiProvider)
          .messages
          .postMessagesThreadsIdRead(id: threadId);
      refreshMessages(_ref);
    } catch (_) {
      // Next time.
    }
  }

  Future<Message> send({
    required String lineId,
    required String to,
    required String text,
  }) async {
    final m = await _ref
        .read(appApiProvider)
        .messages
        .postMessagesSend(
          body: SendInput(lineId: lineId, to: to, text: text),
        );
    refreshMessages(_ref);
    return m;
  }
}

// ------------------------------------------------------------- SMS parts

/// The GSM 03.38 default alphabet, and its extension table (two septets).
const _gsm7 =
    '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
    '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
const _gsm7Ext = '^{}\\[~]|€\f';

/// The most parts a text may take; longer is refused before sending.
const maxSmsParts = 10;

@immutable
class SmsCount {
  const SmsCount({
    required this.units,
    required this.parts,
    required this.perPart,
    required this.unicode,
  });

  /// Septets (GSM-7) or UTF-16 code units (UCS-2).
  final int units;
  final int parts;

  /// 160 or 153 (GSM-7), 70 or 67 (UCS-2).
  final int perPart;
  final bool unicode;

  bool get tooLong => parts > maxSmsParts;

  /// Left in this part.
  int get left => parts * perPart - units;
}

/// GSM-7: 160 in one part, 153 a part when split; anything outside it makes
/// the whole text UCS-2: 70, then 67 a part.
SmsCount smsCount(String text) {
  var septets = 0;
  var gsm = true;
  for (final ch in text.runes) {
    final s = String.fromCharCode(ch);
    if (_gsm7.contains(s)) {
      septets += 1;
    } else if (_gsm7Ext.contains(s)) {
      septets += 2;
    } else {
      gsm = false;
      break;
    }
  }
  if (gsm) {
    if (septets <= 160) {
      return SmsCount(
        units: septets,
        parts: septets == 0 ? 0 : 1,
        perPart: 160,
        unicode: false,
      );
    }
    return SmsCount(
      units: septets,
      parts: (septets / 153).ceil(),
      perPart: 153,
      unicode: false,
    );
  }
  final units = text.length; // UTF-16 code units
  if (units <= 70) {
    return SmsCount(units: units, parts: 1, perPart: 70, unicode: true);
  }
  return SmsCount(
    units: units,
    parts: (units / 67).ceil(),
    perPart: 67,
    unicode: true,
  );
}

/// "42 / 160", "200 / 306 · 2 parts".
String smsCountText(SmsCount c) {
  if (c.parts <= 1) return '${c.units} / ${c.perPart}';
  if (c.tooLong) {
    return '${c.parts} parts, up to $maxSmsParts. Shorten to send.';
  }
  return '${c.units} / ${c.parts * c.perPart} · ${c.parts} parts';
}
