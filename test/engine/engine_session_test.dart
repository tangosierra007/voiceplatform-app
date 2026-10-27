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
