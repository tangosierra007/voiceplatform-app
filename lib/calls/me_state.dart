import 'package:call_engine/call_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_provider.dart';
import '../net/api.dart';
import 'numbers.dart';

/// The numbers this user may show, the default first (`GET /me/caller-ids`).
final callerIdsProvider = FutureProvider<List<CallerId>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return ref.watch(appApiProvider).calls.getMeCallerIds();
});

/// The caller ID picked on the keypad; null is the extension default.
final selectedCallerIdProvider =
    NotifierProvider<SelectedCallerIdNotifier, CallerId?>(
      SelectedCallerIdNotifier.new,
    );

class SelectedCallerIdNotifier extends Notifier<CallerId?> {
  @override
  CallerId? build() {
    final ids = ref.watch(callerIdsProvider).value ?? const [];
    return ids.where((c) => c.isDefault).firstOrNull ?? ids.firstOrNull;
  }

  void pick(CallerId id) => state = id;
}

/// "Calls show 03 5550 1200", or "Calls show Withheld".
String callsShow(CallerId? id) {
  if (id == null) return 'Calls show your number';
  if (id.value == 'withheld') return 'Calls show Withheld';
  return 'Calls show ${formatAuNumber(id.value)}';
}

/// My status for the keypad chip: Available, Do not disturb, Away.
final myStatusProvider = NotifierProvider<MyStatusNotifier, StatusStatus?>(
  MyStatusNotifier.new,
);

class MyStatusNotifier extends Notifier<StatusStatus?> {
  @override
  StatusStatus? build() => ref.watch(meProvider).value?.status.status;

  /// `PUT /me/status` (built by WS1 1.3a; the mock answers today).
  Future<void> set(StatusInputStatus s) async {
    final before = state;
    state = StatusStatus.fromJson(s.json!);
    try {
      final r = await ref
          .read(appApiProvider)
          .me
          .putMeStatus(body: StatusInput(status: s));
      state = r.status;
    } catch (_) {
      state = before;
      rethrow;
    }
  }
}

/// No internet: the engine's registration failed for the network (AppOffline).
final offlineProvider = NotifierProvider<OfflineNotifier, bool>(
  OfflineNotifier.new,
);

class OfflineNotifier extends Notifier<bool> {
  @override
  bool build() {
    final sub = ref
        .watch(callEngineProvider)
        .registration
        .listen(
          (r) => state =
              r.state == RegistrationState.failed &&
              r.failure == RegistrationFailure.network,
        );
    ref.onDispose(sub.cancel);
    return false;
  }

  /// Tests and the debug menu.
  void set(bool offline) => state = offline;
}
