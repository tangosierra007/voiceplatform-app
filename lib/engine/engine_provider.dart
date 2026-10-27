import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vp_linphone/vp_linphone.dart';

import '../auth/auth.dart';
import '../net/api.dart';
import 'fake_call_engine.dart';

/// Which CallEngine the build uses: `--dart-define=VP_ENGINE=linphone|fake`.
/// Debug builds default to the fake (screens without SIP); release and
/// profile builds to liblinphone.
const engineKind = String.fromEnvironment(
  'VP_ENGINE',
  defaultValue: kDebugMode ? 'fake' : 'linphone',
);

/// The app's one CallEngine. Tests override it with a scripted FakeCallEngine.
final callEngineProvider = Provider<CallEngine>((ref) {
  if (engineKind == 'linphone') return VpLinphoneEngine();
  final engine = FakeCallEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// The latest snapshot of one call, ended included.
final callSnapshotProvider = StreamProvider.autoDispose
    .family<CallSnapshot, String>((ref, id) async* {
      final engine = ref.watch(callEngineProvider);
      for (final c in engine.activeCalls) {
        if (c.id == id) yield c;
      }
      yield* engine.calls.where((c) => c.id == id);
    });

/// Every call the engine holds right now, refreshed on each change.
final activeCallsProvider = StreamProvider<List<CallSnapshot>>((ref) async* {
  final engine = ref.watch(callEngineProvider);
  yield engine.activeCalls;
  await for (final _ in engine.calls) {
    yield engine.activeCalls;
  }
});

/// Engine audio routes, for the speaker button and the route sheet.
final audioStateProvider = StreamProvider<AudioState>(
  (ref) => ref.watch(callEngineProvider).audio,
);

/// Starts and registers the engine while someone is signed in: SIP
/// credentials from `POST /devices/me/sip-credentials` go straight into
/// `register()` and are never kept or logged (APP4). Signed out, it
/// unregisters and stops.
final engineSessionProvider = Provider<void>((ref) {
  final engine = ref.watch(callEngineProvider);
  var started = false;

  Future<void> up() async {
    try {
      if (!started) {
        await engine.start();
        started = true;
      }
      final c = await ref
          .read(appApiProvider)
          .device
          .postDevicesMeSipCredentials();
      await engine.register(
        SipAccount(
          authUsername: c.authUsername,
          password: c.password,
          domain: c.domain,
          outboundProxy: c.outboundProxy,
          displayName: c.displayName,
          expiresSeconds: c.expiresSeconds,
          instanceId: c.instanceId,
          // RFC 8599 params come with FCM (WS3 3.2).
        ),
      );
    } catch (_) {
      // Offline or refused: the registration stream says so; retried on the
      // next sign-in or token.
    }
  }

  Future<void> down() async {
    if (!started) return;
    try {
      await engine.unregister();
      await engine.stop();
    } catch (_) {}
    started = false;
  }

  void apply(AuthState s, String? token) {
    if (s is SignedIn && token != null) {
      unawaited(up());
    } else if (s is! SignedIn && s is! AuthStarting) {
      unawaited(down());
    }
  }

  ref.listen<AuthState>(
    authProvider,
    (_, s) => apply(s, ref.read(accessTokenProvider)),
  );
  ref.listen<String?>(accessTokenProvider, (before, t) {
    if (before == null && t != null) apply(ref.read(authProvider), t);
  });
  apply(ref.read(authProvider), ref.read(accessTokenProvider));
});
