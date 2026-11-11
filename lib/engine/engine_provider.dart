import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vp_linphone/vp_linphone.dart';

import '../auth/auth.dart';
import '../calls/call_actions.dart';
import '../net/api.dart';
import 'fake_call_engine.dart';
import 'full_screen_access.dart';

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

/// Each return of the app to the foreground (an [AppLifecycleListener]).
/// Tests override it with their own stream.
final appResumesProvider = Provider<Stream<void>>((ref) {
  final resumes = StreamController<void>.broadcast();
  final listener = AppLifecycleListener(onResume: () => resumes.add(null));
  ref.onDispose(() {
    listener.dispose();
    resumes.close();
  });
  return resumes.stream;
});

/// Starts and registers the engine while someone is signed in: SIP
/// credentials from `POST /devices/me/sip-credentials` go straight into
/// `register()` and are never kept or logged (APP4). Signed out, it
/// unregisters and stops.
///
/// A start or registration that fails (offline, or Android refusing the
/// engine's service while the phone is locked) is tried again the next time
/// the app comes to the foreground, so the API's expiry (decision 170) and
/// fresh credentials always reach the engine; until then only the copy the
/// native side keeps for push wakes registers.
///
/// Not re-run on a timer or on every resume: each `up()` POSTs
/// sip-credentials, which rotates the password and drops the binding.
final engineSessionProvider = Provider<void>((ref) {
  final engine = ref.watch(callEngineProvider);
  var started = false;

  /// Notifications are asked once per process, however often [up] starts
  /// the engine.
  var askedNotifications = false;

  /// The [session] whose sign-in has had the full-screen check. Signing out
  /// clears the "asked" flag, so each new sign-in checks again.
  var fullScreenAskedSession = -1;

  /// The last [up] reached `register()`.
  var registered = false;

  /// Bumped by every sign-out ([down]): a run of [upOnce] from an earlier
  /// session stops at its next step and never registers.
  var session = 0;

  /// The [up] in progress and its session: a second request in the same
  /// session waits for it, never overlaps it; a new session starts its own.
  Future<void>? running;
  var runningSession = -1;

  /// The [down] in progress: a new sign-in waits for its unregister.
  Future<void>? stopping;

  /// The running [up] is in a local step (the engine's start, or
  /// `register()`), which [down] waits for. In its network steps (the FCM
  /// token, the PUT, the POST) [down] doesn't wait: the run stops at its next
  /// check, so an offline sign-out isn't held up by an HTTP timeout.
  var inLocalStep = false;

  /// True when the API took it; the native "not yet sent" flag is cleared then.
  Future<bool> putPushToken(String token) async {
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
      return false;
    }
    await ref.read(pushTokensProvider)?.markTokenSent();
    return true;
  }

  /// Every `POST /devices/me/sip-credentials` rotates the device's SIP
  /// password and the API drops its contacts, so everything that can fail
  /// comes first, and the POST only when `register()` follows at once. The
  /// native side keeps the new account before it registers, so a failed
  /// register still leaves push wakes the new password. A sign-out stops a
  /// run before the POST where it can; after the POST, [down] unregisters,
  /// which clears the kept account.
  Future<void> upOnce(int mine) async {
    bool gone() => mine != session;
    registered = false;
    try {
      final wait = stopping;
      if (wait != null) await wait;
      if (gone()) return;
      var notifications = Future<void>.value();
      if (!started) {
        inLocalStep = true;
        try {
          await engine.start();
        } finally {
          inLocalStep = false;
        }
        started = true;
        if (gone()) return;
        if (!askedNotifications) {
          askedNotifications = true;
          // Incoming-call notifications need it on Android 13+ (WS3 3.2):
          // asked once signed in, when the app can start ringing.
          // Then the microphone (FU43): asked only when a call started, a
          // first call answered on a locked phone raised the prompt behind
          // the lock screen and went out with no audio. Refused here, the
          // call screens ask again as before.
          final perms = ref.read(micPermissionProvider);
          notifications = perms.requestNotifications().then((_) async {
            try {
              if (!gone() && !await perms.isGranted()) await perms.request();
            } catch (_) {}
          });
        }
      }
      // Then, once that is answered, full-screen access, so a call can show
      // on a locked phone (Android 14+): on every sign-in, since signing out
      // forgets that it was asked.
      if (fullScreenAskedSession != mine) {
        fullScreenAskedSession = mine;
        unawaited(
          notifications.whenComplete(
            () => ref.read(fullScreenPromptProvider.notifier).afterSignIn(),
          ),
        );
      }
      // The FCM token for RFC 8599 (pn-provider fcm, pn-param
      // voiceplatform-app) and for the API; null without push (fake engine).
      final push = ref.read(pushTokensProvider);
      final token = await push?.start();
      if (gone()) return;
      // A token the background registration (after a restart or an update)
      // put in the SIP contact while the app wasn't running: the API sends
      // its pushes (signed_out, voicemail, message) to the old one until it
      // has this. Sent first, whether or not the registration below works.
      if (token != null && push != null && await push.tokenUnsent()) {
        await putPushToken(token);
      }
      // Last stop before the POST (it rotates the credentials).
      if (gone()) return;
      final c = await ref
          .read(appApiProvider)
          .device
          .postDevicesMeSipCredentials();
      // Signed out meanwhile: no register; [down] is unregistering, which
      // clears the account the native side keeps.
      if (gone()) return;
      inLocalStep = true;
      try {
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
      } finally {
        inLocalStep = false;
      }
      registered = true;
      if (gone()) return;
      if (token != null) await putPushToken(token);
    } catch (_) {
      // Offline or refused (Android may refuse the engine's service while
      // the phone is locked): the registration stream says so; retried on
      // the next resume, sign-in or token.
    }
  }

  Future<void> up() {
    final now = running;
    if (now != null && runningSession == session) return now;
    final mine = session;
    final run = upOnce(mine);
    running = run;
    runningSession = mine;
    unawaited(
      run.whenComplete(() {
        if (identical(running, run)) running = null;
      }),
    );
    return run;
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
  ///
  /// A run of [up] still going is stopped first (the session moves on). It is
  /// waited for only in a local step ([inLocalStep]): in `register()`, so the
  /// register can never come after this unregister. In a network step it
  /// can't reach `register()` any more: it checks the session first.
  Future<void> downOnce() async {
    session++;
    registered = false;
    final run = running;
    if (run != null && inLocalStep) {
      try {
        await run;
      } catch (_) {}
    }
    // Read before the unregister: its `cleared` resets [started].
    final wasStarted = started;
    try {
      await engine.unregister();
    } catch (_) {}
    if (!wasStarted && !started) return;
    try {
      await engine.stop();
    } catch (_) {}
    started = false;
  }

  Future<void> down() {
    final run = downOnce();
    stopping = run;
    unawaited(
      run.whenComplete(() {
        if (identical(stopping, run)) stopping = null;
      }),
    );
    return run;
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
  // Registration cleared: an unregister, or the engine's service stopped
  // with an account (the native side reports `cleared` then). The next
  // resume starts the engine (a no-op when it runs) and registers again if
  // still signed in. Not on `none`: a new account reports it before it
  // registers.
  final cleared = engine.registration.listen((e) {
    if (e.state != RegistrationState.cleared) return;
    registered = false;
    started = false;
  });
  ref.onDispose(cleared.cancel);

  // Back in the foreground after a start or registration that didn't go
  // through: try again, with fresh credentials.
  final resumes = ref.read(appResumesProvider).listen((_) {
    if (registered) return;
    final s = ref.read(authProvider);
    if (s is SignedIn && ref.read(accessTokenProvider) != null) unawaited(up());
  });
  ref.onDispose(resumes.cancel);
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
