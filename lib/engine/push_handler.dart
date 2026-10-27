import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth.dart';
import '../auth/version.dart';
import '../features/messages/messages_data.dart';
import '../features/recents/recents_data.dart';
import '../net/api.dart';
import '../shell/shell_status.dart';
import 'phone_extras.dart';

/// Acts on the app's data pushes. They carry no content (APP5): each one
/// only says what to fetch again.
final pushHandlerProvider = Provider<void>((ref) {
  final extras = ref.watch(phoneExtrasProvider);

  void handle(VpPushMessage p) {
    switch (p.type) {
      case VpPushType.message:
        refreshMessages(ref);
      case VpPushType.voicemail:
        ref.invalidate(voicemailBoxesProvider);
        ref.invalidate(voicemailMessagesProvider);
        ref.invalidate(historyProvider);
        ref.read(liveBadgesProvider.notifier).forget();
        ref.invalidate(meProvider);
      case VpPushType.signedOut:
        unawaited(ref.read(authProvider.notifier).onSignedOutPush());
      case VpPushType.config:
        unawaited(ref.read(appConfigProvider.notifier).check());
    }
  }

  final sub = extras.pushes.listen(handle);
  ref.onDispose(sub.cancel);
  unawaited(
    extras.takePendingPushes().then((list) {
      for (final p in list) {
        handle(p);
      }
    }),
  );
});
