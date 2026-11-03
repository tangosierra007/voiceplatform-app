// Signed in, the engine starts and registers with the device's SIP identity
// and the FCM token as RFC 8599 params; the token goes to the API, and again
// on every refresh. Notifications are asked for once.
import 'dart:async';
import 'dart:io' show HttpOverrides;

import 'package:call_engine/call_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/calls/call_actions.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';
import 'package:vp_linphone/vp_linphone.dart';

import '../../tool/mock_server/fixtures.dart';
import '../../tool/mock_server/server.dart';
import '../support/call_fakes.dart';
import '../support/fakes.dart';

class _Tokens implements PushTokenSource {
  _Tokens(this.token);
  String? token;
  final refresh = StreamController<String>.broadcast();

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get tokenRefresh => refresh.stream;
}

void main() {
  late MockServer server;

  setUpAll(() async {
    HttpOverrides.global = null;
    server = await MockServer.start(port: 0);
  });
  tearDownAll(() => server.close());

  test(
    'register carries the FCM params; the token reaches the API, refreshed too',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final engine = FakeCallEngine(registerAfter: Duration.zero);
      final source = _Tokens('fcm-token-1');
      final push = VpPushTokens(engine: engine, source: source);
      final mic = FakeMic();
      final store = MemorySessionStore();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          sessionStoreProvider.overrideWithValue(store),
          deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
          callEngineProvider.overrideWithValue(engine),
          pushTokensProvider.overrideWithValue(push),
          micPermissionProvider.overrideWithValue(mic),
          appResumesProvider.overrideWithValue(const Stream.empty()),
          apiConfigProvider.overrideWithValue(
            ApiConfig(
              baseUrl: server.baseUri.toString(),
              platform: 'android',
              appVersion: '1.0.0',
              deviceModel: 'Pixel 8',
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(engineSessionProvider);
      c.read(authProvider);
      await pumpEventQueue();

      await c
          .read(authProvider.notifier)
          .completeWithQr(SignInFixtures.qrToken);
      await pumpEventQueue(times: 50);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(engine.registrationState, RegistrationState.ok);
      expect(engine.registeredAs, 'mock-202-pixel8@sip.demo-co.example');
      expect(engine.pushParams!.provider, 'fcm');
      expect(engine.pushParams!.prid, 'fcm-token-1');
      expect(engine.pushParams!.param, 'voiceplatform-app');
      expect(server.lastPushToken, 'fcm-token-1');
      expect(mic.notificationAsks, 1);

      source.refresh.add('fcm-token-2');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        engine.pushParams!.prid,
        'fcm-token-2',
        reason: 'updatePush, no drop',
      );
      expect(server.lastPushToken, 'fcm-token-2');
      await engine.dispose();
    },
  );

  test('a cold start revoked before the engine starts still clears its '
      'stored SIP account', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final engine = _SpyEngine();
    final store = MemorySessionStore()
      ..session = StoredSession(
        deviceId: uid(0x6, 1),
        refreshToken: SignInFixtures.revokedRefreshToken,
      );
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(store),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        callEngineProvider.overrideWithValue(engine),
        pushTokensProvider.overrideWithValue(null),
        micPermissionProvider.overrideWithValue(FakeMic()),
        appResumesProvider.overrideWithValue(const Stream.empty()),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: server.baseUri.toString(),
            platform: 'android',
            appVersion: '1.0.0',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(engineSessionProvider);
    c.read(authProvider);
    for (var i = 0; i < 40 && c.read(authProvider) is! SignedOutRemotely; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await pumpEventQueue();
    expect(c.read(authProvider), isA<SignedOutRemotely>());
    expect(engine.starts, 0);
    expect(engine.unregisters, greaterThanOrEqualTo(1));
    expect(store.session, isNull);
  });

  // The background registration (after a restart or an update) put a rotated
  // FCM token in the SIP contact with no app running: the next start sends it
  // to the API before anything else, and clears the native flag only then.
  // Each with its own mock server: the QR sign-in token works once.
  Future<(MockServer, _Ledger)> signInWith({
    required bool unsent,
    required FakeCallEngine engine,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final own = await MockServer.start(port: 0);
    addTearDown(own.close);
    final ledger = _Ledger(unsent);
    final push = VpPushTokens(
      engine: engine,
      source: _Tokens('fcm-token-3'),
      ledger: ledger,
    );
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(MemorySessionStore()),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        callEngineProvider.overrideWithValue(engine),
        pushTokensProvider.overrideWithValue(push),
        micPermissionProvider.overrideWithValue(FakeMic()),
        appResumesProvider.overrideWithValue(const Stream.empty()),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: own.baseUri.toString(),
            platform: 'android',
            appVersion: '1.0.0',
            deviceModel: 'Pixel 8',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(engineSessionProvider);
    c.read(authProvider);
    await pumpEventQueue();
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return (own, ledger);
  }

  test('an unsent token goes to the API on start even when the SIP '
      'registration fails, and the flag is cleared', () async {
    final engine = _FailingRegisterEngine();
    final (own, ledger) = await signInWith(unsent: true, engine: engine);
    expect(engine.registerAttempts, greaterThanOrEqualTo(1));
    expect(own.lastPushToken, 'fcm-token-3');
    expect(ledger.flag, isFalse);
    await engine.dispose();
  });

  test('with nothing unsent, a failed registration sends no token and '
      'the flag is left alone', () async {
    final engine = _FailingRegisterEngine();
    final (own, ledger) = await signInWith(unsent: false, engine: engine);
    expect(own.lastPushToken, isNull);
    expect(ledger.marks, 0);
    await engine.dispose();
  });

  test('the usual PUT after registering clears the flag too', () async {
    final engine = FakeCallEngine(registerAfter: Duration.zero);
    final (own, ledger) = await signInWith(unsent: true, engine: engine);
    expect(engine.registrationState, RegistrationState.ok);
    expect(own.lastPushToken, 'fcm-token-3');
    expect(ledger.flag, isFalse);
    expect(ledger.marks, greaterThanOrEqualTo(1));
    await engine.dispose();
  });
  // Android refuses the engine's service while the phone is locked: the
  // start fails, nothing registers but the native copy (the old expiry).
  // Back in the foreground, the app starts and registers with fresh
  // credentials, once, and no two runs overlap.
  test('a start that failed is tried again on resume, with fresh '
      'credentials; one run at a time, none once registered', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final own = await MockServer.start(port: 0);
    addTearDown(own.close);
    final engine = _FlakyStartEngine(failures: 1);
    final resumes = StreamController<void>.broadcast();
    addTearDown(resumes.close);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(MemorySessionStore()),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        callEngineProvider.overrideWithValue(engine),
        pushTokensProvider.overrideWithValue(null),
        micPermissionProvider.overrideWithValue(FakeMic()),
        appResumesProvider.overrideWithValue(resumes.stream),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: own.baseUri.toString(),
            platform: 'android',
            appVersion: '1.0.0',
            deviceModel: 'Pixel 8',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(engineSessionProvider);
    c.read(authProvider);
    await pumpEventQueue();
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(engine.startAttempts, 1);
    expect(engine.accounts, isEmpty, reason: 'the start failed: no register');

    // Two resumes at once: one run.
    resumes
      ..add(null)
      ..add(null);
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.startAttempts, 2);
    expect(engine.accounts, hasLength(1));
    expect(engine.registrationState, RegistrationState.ok);
    expect(
      engine.accounts.single.expiresSeconds,
      600,
      reason: "the API's expiry (the mock server's), not a stored one",
    );

    // Registered: a later resume does nothing.
    resumes.add(null);
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(engine.startAttempts, 2);
    expect(engine.accounts, hasLength(1));
    await engine.dispose();
  });

  test('a registration that failed is tried again on resume', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final own = await MockServer.start(port: 0);
    addTearDown(own.close);
    final engine = _FlakyStartEngine(failures: 0, registerFailures: 1);
    final resumes = StreamController<void>.broadcast();
    addTearDown(resumes.close);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(MemorySessionStore()),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        callEngineProvider.overrideWithValue(engine),
        pushTokensProvider.overrideWithValue(null),
        micPermissionProvider.overrideWithValue(FakeMic()),
        appResumesProvider.overrideWithValue(resumes.stream),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: own.baseUri.toString(),
            platform: 'android',
            appVersion: '1.0.0',
            deviceModel: 'Pixel 8',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(engineSessionProvider);
    c.read(authProvider);
    await pumpEventQueue();
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.registerAttempts, 1);
    expect(engine.accounts, isEmpty);

    resumes.add(null);
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.registerAttempts, 2);
    expect(engine.accounts, hasLength(1));
    expect(engine.startAttempts, 1, reason: 'already started: not again');
    await engine.dispose();
  });
  // Sign-outs during up(), and the credentials POST that rotates the
  // password (WS6 and mobile-lead on #52).
  Future<(ProviderContainer, StreamController<void>)> session(
    _GatedEngine engine,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final own = await MockServer.start(port: 0);
    addTearDown(own.close);
    final resumes = StreamController<void>.broadcast();
    addTearDown(resumes.close);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(MemorySessionStore()),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        callEngineProvider.overrideWithValue(engine),
        pushTokensProvider.overrideWithValue(null),
        micPermissionProvider.overrideWithValue(FakeMic()),
        appResumesProvider.overrideWithValue(resumes.stream),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: own.baseUri.toString(),
            platform: 'android',
            appVersion: '1.0.0',
            deviceModel: 'Pixel 8',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(engineSessionProvider);
    c.read(authProvider);
    await pumpEventQueue();
    await pumpEventQueue(times: 50);
    // The cold start, signed out, unregisters (clearing any kept account).
    engine.log.clear();
    return (c, resumes);
  }

  Future<void> settle() async {
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  test('a sign-out before the credentials POST stops the run: no POST, no '
      'register; the next sign-in starts a fresh run', () async {
    final engine = _GatedEngine()..startGate = Completer<void>();
    final (c, _) = await session(engine);
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await settle();
    expect(engine.sinceStart, ['start']);

    await c.read(authProvider.notifier).signOutLocally();
    await settle();
    expect(engine.sinceStart, ['start'], reason: 'down() waits for the run');
    engine.startGate!.complete();
    await settle();
    expect(engine.sinceStart, ['start', 'unregister']);
    expect(engine.attempted, isEmpty);

    // A new sign-in: its own run, not the old one.
    await c
        .read(authProvider.notifier)
        .requestEmail(SignInFixtures.advancedEmail);
    await c.read(authProvider.notifier).completeWithCode(SignInFixtures.code);
    await settle();
    expect(engine.log.last, 'register');
    expect(engine.attempted, hasLength(1));
    expect(engine.registrationState, RegistrationState.ok);
    await engine.dispose();
  });

  test('a sign-out while register() runs: the unregister comes after it, '
      'never a register after the unregister', () async {
    final engine = _GatedEngine()..registerGate = Completer<void>();
    final (c, _) = await session(engine);
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await settle();
    expect(engine.sinceStart, ['start', 'register']);

    await c.read(authProvider.notifier).signOutLocally();
    await settle();
    expect(engine.sinceStart, ['start', 'register'], reason: 'down() waits');
    engine.registerGate!.complete();
    await settle();
    expect(engine.sinceStart.sublist(0, 3), [
      'start',
      'register',
      'unregister',
    ]);
    expect(engine.sinceStart.skip(2).contains('register'), isFalse);
    await engine.dispose();
  });

  test('a register that fails after the POST got the rotated credentials; '
      'the resume retries with newer ones', () async {
    // The native side keeps the account before it registers
    // (AccountSetup.keepThenRegister, Kotlin-tested), so push wakes have the
    // POST's new password even though this register failed.
    final engine = _GatedEngine()..registerFailures = 1;
    final (c, resumes) = await session(engine);
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await settle();
    expect(engine.attempted, hasLength(1));
    expect(engine.attempted.single.authUsername, startsWith('mock-'));
    expect(engine.attempted.single.password, isNotEmpty);
    expect(engine.registrationState, isNot(RegistrationState.ok));

    resumes.add(null);
    await settle();
    expect(engine.attempted, hasLength(2));
    expect(
      engine.attempted[1].password,
      isNot(engine.attempted[0].password),
      reason: 'each POST rotates the password',
    );
    expect(engine.registrationState, RegistrationState.ok);
    await engine.dispose();
  });

  test('a cleared registration lets the next resume register again', () async {
    final engine = _GatedEngine();
    final (c, resumes) = await session(engine);
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await settle();
    expect(engine.attempted, hasLength(1));
    resumes.add(null);
    await settle();
    expect(engine.attempted, hasLength(1), reason: 'registered: no new POST');

    await engine.unregister(); // as a signed_out push or native stop would
    engine.log.clear();
    resumes.add(null);
    await settle();
    expect(engine.attempted, hasLength(2));
    await engine.dispose();
  });
}

class _SpyEngine extends FakeCallEngine {
  int starts = 0;
  int unregisters = 0;

  @override
  Future<void> start() {
    starts++;
    return super.start();
  }

  @override
  Future<void> unregister() {
    unregisters++;
    return super.unregister();
  }
}

class _Ledger implements PushTokenLedger {
  _Ledger(this.flag);
  bool flag;
  int marks = 0;

  @override
  Future<bool> unsent() async => flag;

  @override
  Future<void> markSent() async {
    marks++;
    flag = false;
  }
}

class _FailingRegisterEngine extends FakeCallEngine {
  int registerAttempts = 0;

  @override
  Future<void> register(SipAccount account) async {
    registerAttempts++;
    throw StateError('refused in the test');
  }
}

/// start() fails [failures] times (Android refusing the service), register()
/// [registerFailures] times; the accounts that did register are kept.
class _FlakyStartEngine extends FakeCallEngine {
  _FlakyStartEngine({required this.failures, this.registerFailures = 0})
    : super(registerAfter: Duration.zero);
  int failures;
  int registerFailures;
  int startAttempts = 0;
  int registerAttempts = 0;
  final accounts = <SipAccount>[];

  @override
  Future<void> start() async {
    startAttempts++;
    if (failures > 0) {
      failures--;
      throw StateError('startForegroundService() not allowed');
    }
    return super.start();
  }

  @override
  Future<void> register(SipAccount account) async {
    registerAttempts++;
    if (registerFailures > 0) {
      registerFailures--;
      throw StateError('offline');
    }
    accounts.add(account);
    return super.register(account);
  }
}

/// Logs start, register and unregister in order; [startGate] and
/// [registerGate] hold those calls until completed; register() fails
/// [registerFailures] times after taking the account.
class _GatedEngine extends FakeCallEngine {
  _GatedEngine() : super(registerAfter: Duration.zero);
  Completer<void>? startGate;
  Completer<void>? registerGate;
  int registerFailures = 0;
  final log = <String>[];
  final attempted = <SipAccount>[];

  /// [log] from the first start (signing in passes through signed-out
  /// states, whose down() unregisters first).
  List<String> get sinceStart {
    final i = log.indexOf('start');
    return i < 0 ? const [] : log.sublist(i);
  }

  @override
  Future<void> start() async {
    log.add('start');
    await startGate?.future;
    return super.start();
  }

  @override
  Future<void> register(SipAccount account) async {
    log.add('register');
    attempted.add(account);
    await registerGate?.future;
    if (registerFailures > 0) {
      registerFailures--;
      throw StateError('register failed');
    }
    return super.register(account);
  }

  @override
  Future<void> unregister() {
    log.add('unregister');
    return super.unregister();
  }
}
