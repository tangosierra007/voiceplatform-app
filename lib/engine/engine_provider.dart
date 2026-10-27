import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vp_linphone/vp_linphone.dart';

import '../auth/auth.dart';
import '../calls/call_actions.dart';
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

  Future<void> putPushToken(String token) async {
    try {
      await ref
          .read(appApiProvider)
          .device
          .putDevicesMePushToken(
            body: PushTokenInput(
              provider: PushTokenInputProvider.fcm,
              token: token,
            ),
          );
    } catch (_) {
      // Sent again with the next token or sign-in.
    }
  }

  Future<void> up() async {
    try {
      if (!started) {
        await engine.start();
        started = true;
        // Incoming-call notifications need it on Android 13+ (WS3 3.2):
        // asked once signed in, when the app can start ringing.
        unawaited(ref.read(micPermissionProvider).requestNotifications());
      }
      // The FCM token for RFC 8599 (pn-provider fcm, pn-param
      // voiceplatform-app) and for the API; null without push (fake engine).
      final push = ref.read(pushTokensProvider);
      final token = await push?.start();
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
          push: token == null ? null : VpPushTokens.paramsFor(token),
        ),
      );
      if (token != null) await putPushToken(token);
    } catch (_) {
      // Offline or refused: the registration stream says so; retried on the
      // next sign-in or token.
    }
  }

  // A refreshed token: VpPushTokens has already updated the engine's
  // contact; the API gets it too.
  final push = ref.read(pushTokensProvider);
  if (push != null) {
    final sub = push.tokens.listen((t) {
      if (ref.read(authProvider) is SignedIn) unawaited(putPushToken(t));
    });
    ref.onDispose(sub.cancel);
  }

  /// Every sign-out path, even when the engine never started in this process
  /// (a cold start that refreshes into `device_revoked`): `unregister()` also
  /// clears the SIP account the native side keeps for push wakes, so a later
  /// push can't register it again.
  Future<void> down() async {
    try {
      await engine.unregister();
    } catch (_) {}
    if (!started) return;
    try {
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

/// The FCM token (VpPushTokens) with the real engine; none with the fake.
final pushTokensProvider = Provider<VpPushTokens?>((ref) {
  final engine = ref.watch(callEngineProvider);
  if (engine is! VpLinphoneEngine) return null;
  final p = VpPushTokens(engine: engine);
  ref.onDispose(p.dispose);
  return p;
});

/// Screen requests from the incoming-call notification and full-screen
/// intent (WS3 3.2): show AppIncoming, or the call answered from the
/// notification. Nothing with the fake engine.
abstract interface class EngineUi {
  Stream<VpUiRequest> get requests;

  /// The request a cold start came with, once.
  Future<VpUiRequest?> take();
}

class _LinphoneUi implements EngineUi {
  const _LinphoneUi(this.engine);
  final VpLinphoneEngine engine;

  @override
  Stream<VpUiRequest> get requests => engine.uiRequests;

  @override
  Future<VpUiRequest?> take() async {
    try {
      return await engine.takeUiRequest();
    } catch (_) {
      return null;
    }
  }
}

class _NoUi implements EngineUi {
  const _NoUi();

  @override
  Stream<VpUiRequest> get requests => const Stream.empty();

  @override
  Future<VpUiRequest?> take() async => null;
}

final engineUiProvider = Provider<EngineUi>((ref) {
  final engine = ref.watch(callEngineProvider);
  return engine is VpLinphoneEngine ? _LinphoneUi(engine) : const _NoUi();
});
