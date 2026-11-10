import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth.dart' show clockProvider;
import '../theme/theme_preference.dart';
import 'engine_provider.dart';
import 'phone_extras.dart';

/// Whether incoming calls may show over the lock screen (full-screen
/// notifications, Android 14 and later). True until the first check answers,
/// and wherever the engine can't tell, so nothing nags by mistake. Checked
/// again each time the app comes back to the foreground: back from Settings,
/// or taken away while the app was in the background.
final fullScreenAccessProvider =
    NotifierProvider<FullScreenAccessNotifier, bool>(
      FullScreenAccessNotifier.new,
    );

class FullScreenAccessNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(phoneExtrasProvider);
    final sub = ref.watch(appResumesProvider).listen((_) => check());
    ref.onDispose(sub.cancel);
    scheduleMicrotask(check);
    return true;
  }

  /// Asks the engine now; the answer is also the new state.
  Future<bool> check() async {
    // Rebuilt or disposed before this ran (it is also a microtask).
    if (!ref.mounted) return true;
    final allowed = await ref.read(phoneExtrasProvider).canUseFullScreen();
    if (ref.mounted) state = allowed;
    return allowed;
  }
}

/// The "Let calls show on your locked screen" sheet: true while it waits to
/// be shown. The tabs show it and call [FullScreenPromptNotifier.shown].
///
/// It asks once after sign-in (the flag goes with everything else at
/// sign-out), and again after a call that rang while access was denied, at
/// most once a day.
final fullScreenPromptProvider =
    NotifierProvider<FullScreenPromptNotifier, bool>(
      FullScreenPromptNotifier.new,
    );

class FullScreenPromptNotifier extends Notifier<bool> {
  static const shownKey = 'vp.fullScreenPromptShown';
  static const dayKey = 'vp.fullScreenPromptDay';

  @override
  bool build() {
    final extras = ref.watch(phoneExtrasProvider);
    final engine = ref.watch(callEngineProvider);
    // Calls that rang as a notification only: the sheet once none is left.
    // Known two ways: the engine's report, which is lost when no Flutter
    // engine was attached (app swiped away, the call came by push), and
    // access being denied while an incoming call is seen, which covers the
    // app starting at Answer, mid-call.
    final rang = <String, Future<bool>>{};
    var pending = false;
    Future<void> onCall(CallSnapshot c) async {
      if (c.direction == CallDirection.incoming || rang.containsKey(c.id)) {
        final denied = rang[c.id] ??= extras.canUseFullScreen().then(
          (allowed) => !allowed,
          onError: (_) => false,
        );
        if (c.state != CallState.ended) return;
        if (await denied) pending = true;
        rang.remove(c.id);
      } else if (c.state != CallState.ended) {
        // An outgoing call: only its end matters, to show a sheet put off
        // while it was up.
        return;
      }
      final left = engine.activeCalls.any(
        (o) => o.id != c.id && o.state != CallState.ended,
      );
      if (pending && !left) {
        pending = false;
        await _afterDeniedCall();
      }
    }

    final subs = [
      extras.fullScreenDeniedCalls.listen((id) {
        rang[id] = Future.value(true);
      }),
      engine.calls.listen((c) => unawaited(onCall(c))),
    ];
    for (final c in engine.activeCalls) {
      unawaited(onCall(c));
    }
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    return false;
  }

  String _today() {
    final d = ref.read(clockProvider)();
    return '${d.year}-${d.month}-${d.day}';
  }

  Future<bool> _denied() async =>
      !await ref.read(fullScreenAccessProvider.notifier).check();

  /// Straight after the notifications prompt: once, if access is denied.
  Future<void> afterSignIn() async {
    try {
      if (!await _denied() || !ref.mounted) return;
      if (ref.read(sharedPreferencesProvider).getBool(shownKey) ?? false) {
        return;
      }
      state = true;
    } catch (_) {
      // No answer or no storage: better not to ask than to ask wrongly.
    }
  }

  Future<void> _afterDeniedCall() async {
    if (!ref.mounted) return;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (prefs.getString(dayKey) == _today()) return;
      if (!await _denied() || !ref.mounted) return;
      state = true;
    } catch (_) {
      // As above.
    }
  }

  /// Allowed by the time the sheet would show: nothing to ask, and nothing
  /// remembered.
  void skip() => state = false;

  /// The sheet is on screen: not again after sign-in, nor again today.
  Future<void> shown() async {
    state = false;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(shownKey, true);
    await prefs.setString(dayKey, _today());
  }
}
