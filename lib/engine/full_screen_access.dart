import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth.dart';
import '../net/api.dart';
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

  /// Which sheet showed last: `signIn` or `afterCall`.
  static const kindKey = 'vp.fullScreenPromptKind';
  static const _signIn = 'signIn';
  static const _afterCall = 'afterCall';

  /// When this sign-in began: the history check's baseline when no sheet
  /// has shown yet (access was allowed at sign-in, turned off later).
  static const sinceKey = 'vp.fullScreenPromptSince';

  /// History is read again only after this long: opening the app over and
  /// over while denied doesn't ask the API each time.
  static const historyEvery = Duration(minutes: 2);

  bool _historyBusy = false;
  DateTime? _historyReadAt;

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
    // Calls the app never saw: history, each time the app opens.
    final resumes = ref
        .watch(appResumesProvider)
        .listen((_) => unawaited(checkHistory()));
    ref.onDispose(resumes.cancel);
    ref.listen(accessTokenProvider, (was, token) {
      if (was == null && token != null) unawaited(checkHistory());
    });
    scheduleMicrotask(checkHistory);
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

  DateTime _now() => ref.read(clockProvider)();

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// When the sheet last showed, from [dayKey]: a full timestamp, or from
  /// an earlier build only the day (`2026-11-10`), read as the end of that
  /// day, so a call that day never asks again. Null when never shown.
  DateTime? _lastShown() {
    final v = ref.read(sharedPreferencesProvider).getString(dayKey);
    if (v == null) return null;
    final day = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(v);
    if (day != null) {
      final [y, m, d] = [for (var i = 1; i <= 3; i++) int.parse(day[i]!)];
      return DateTime(y, m, d + 1).subtract(const Duration(milliseconds: 1));
    }
    return DateTime.tryParse(v);
  }

  /// The once-a-day limit: only a sheet after a call uses up the day, not
  /// the one after sign-in. With no [kindKey] (an earlier build), the last
  /// showing counts as after a call, so it never asks twice in a day.
  bool _afterCallShownToday() {
    final kind = ref.read(sharedPreferencesProvider).getString(kindKey);
    if (kind == _signIn) return false;
    final last = _lastShown();
    return last != null && _sameDay(last.toLocal(), _now().toLocal());
  }

  /// What the waiting sheet is for: [_signIn] or [_afterCall].
  String _kind = _afterCall;

  void _ask(String kind) {
    _kind = kind;
    state = true;
  }

  Future<bool> _denied() async =>
      !await ref.read(fullScreenAccessProvider.notifier).check();

  /// Straight after the notifications prompt: once, if access is denied.
  Future<void> afterSignIn() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (prefs.getString(sinceKey) == null) {
        await prefs.setString(sinceKey, _now().toIso8601String());
      }
      if (!await _denied() || !ref.mounted) return;
      if (ref.read(sharedPreferencesProvider).getBool(shownKey) ?? false) {
        return;
      }
      _ask(_signIn);
    } catch (_) {
      // No answer or no storage: better not to ask than to ask wrongly.
    }
  }

  Future<void> _afterDeniedCall() async {
    if (!ref.mounted) return;
    try {
      if (_afterCallShownToday()) return;
      if (!await _denied() || !ref.mounted) return;
      _ask(_afterCall);
    } catch (_) {
      // As above.
    }
  }

  /// On opening the app (start and each resume), still denied: an incoming
  /// call in history since the sheet last showed (or, if it never has,
  /// since sign-in) asks again, at most once a day. This catches a call the
  /// app never saw, answered from the lock screen without its screens
  /// coming to the front. One read at a time, and none within
  /// [historyEvery] of the last. A failed history read asks nothing.
  Future<void> checkHistory() async {
    if (!ref.mounted || state || _historyBusy) return;
    _historyBusy = true;
    try {
      if (ref.read(accessTokenProvider) == null) return;
      if (ref.read(authProvider) is! SignedIn) return;
      final since = DateTime.tryParse(
        ref.read(sharedPreferencesProvider).getString(sinceKey) ?? '',
      );
      final shown = _lastShown();
      final last = since == null
          ? shown
          : shown == null || since.isAfter(shown)
          ? since
          : shown;
      if (last == null || _afterCallShownToday()) return;
      final readAt = _historyReadAt;
      final now = _now();
      if (readAt != null && now.difference(readAt) < historyEvery) return;
      if (!await _denied() || !ref.mounted) return;
      _historyReadAt = now;
      final latest = await ref.read(latestIncomingCallProvider)();
      if (!ref.mounted || latest == null || !latest.isAfter(last)) return;
      if (_afterCallShownToday()) return;
      _ask(_afterCall);
    } catch (_) {
      // Offline or refused: no sheet.
    } finally {
      _historyBusy = false;
    }
  }

  /// Allowed by the time the sheet would show: nothing to ask, and nothing
  /// remembered.
  void skip() => state = false;

  /// The sheet is on screen: not again after sign-in, only for incoming
  /// calls after this moment, and (after a call) not again today.
  Future<void> shown() async {
    state = false;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(shownKey, true);
    await prefs.setString(dayKey, _now().toIso8601String());
    await prefs.setString(kindKey, _kind);
  }
}

/// The time of the newest incoming call in the first page of history
/// (`GET /history`, newest first, 10 entries), or null with none. Tests
/// replace it.
final latestIncomingCallProvider = Provider<Future<DateTime?> Function()>(
  (ref) => () async {
    final page = await ref.read(appApiProvider).history.getHistory(limit: 10);
    DateTime? latest;
    for (final e in page.items) {
      if (e.direction != HistoryEntryDirection.incoming) continue;
      if (latest == null || e.at.isAfter(latest)) latest = e.at;
    }
    return latest;
  },
);
