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
