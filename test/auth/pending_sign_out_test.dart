// A sign-out made with no network (spec 22, "Sign out with no network"):
// kept signed on the phone, sent once on the next connection, never twice,
// against the mock server (real HTTP on a local socket). "Offline" is an API
// address nothing listens on.
import 'dart:io' show HttpOverrides;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/pending_sign_out.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart';
import '../../tool/mock_server/server.dart';
import '../support/fakes.dart';

void main() {
  late MockServer server;
  var now = DateTime.now();
  DateTime clock() => now;
  const offline = 'http://127.0.0.1:1/app/v1';
  const device = '6f1c2b9e-3a4d-4e5f-8a9b-0c1d2e3f4a5b';
  const refreshToken = 'held-refresh-token-0123456789abcdef0123456789';

  setUpAll(() async {
    HttpOverrides.global = null;
    server = await MockServer.start(
      port: 0,
      now: clock,
      resendAfter: const Duration(seconds: 60),
      accessLifetime: const Duration(minutes: 15),
      minimumVersion: '1.0.0',
      recommendedVersion: '1.0.2',
    );
  });
  tearDownAll(() => server.close());

  late MemoryPendingSignOutStore pending;
  late FakeDeviceKeys keys;

  setUp(() {
    now = DateTime.now();
    pending = MemoryPendingSignOutStore();
    server.lateSignOuts.clear();
    server.lateSignOutDown = false;
  });

  /// One run of the app: its own session store, the shared pending store.
  Future<ProviderContainer> run({
    required String baseUrl,
    StoredSession? session,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    keys = FakeDeviceKeys();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(MemorySessionStore(session)),
        pendingSignOutStoreProvider.overrideWithValue(pending),
        deviceKeysProvider.overrideWithValue(keys),
        clockProvider.overrideWithValue(clock),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: baseUrl,
            platform: 'android',
            appVersion: '1.0.3',
            deviceModel: 'Pixel 8',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(authProvider);
    await pumpEventQueue();
    await c.read(authProvider.notifier).sendPendingSignOut();
    return c;
  }

  /// Signed in, then Sign out with no network.
  Future<void> signOutOffline() async {
    final c = await run(
      baseUrl: offline,
      session: const StoredSession(
        deviceId: device,
        refreshToken: refreshToken,
      ),
    );
    expect(c.read(authProvider), isA<SignedIn>());
    await c.read(authProvider.notifier).signOut();
    expect(c.read(authProvider), isA<NotSignedIn>());
  }

  test('queued offline, sent once on reconnect, never twice', () async {
    await signOutOffline();
    // Signed with the device key before it went; the phone is cleared.
    final p = pending.pending!;
    expect(p.deviceId, device);
    expect(p.refreshToken, refreshToken);
    // (The start's refresh signed too: only one sign-out message.)
    expect(keys.signed.where((m) => m.startsWith('sign-out.')), [
      PendingSignOut.message(device, refreshToken, p.timestamp),
    ]);
    expect(keys.deletes, 1);
    expect(p.toString(), isNot(contains(refreshToken)));
    expect(p.toString(), isNot(contains(p.signature)));

    // Still offline at the next start: kept, nothing sent.
    await run(baseUrl: offline);
    expect(pending.pending, isNotNull);
    expect(server.lateSignOuts, isEmpty);

    // Back online: sent at start, with exactly what was signed, then dropped.
    now = now.add(const Duration(days: 3));
    final c = await run(baseUrl: server.baseUri.toString());
    expect(server.lateSignOuts, hasLength(1));
    final sent = server.lateSignOuts.single;
    expect(sent['deviceId'], device);
    expect(sent['refreshToken'], refreshToken);
    expect(sent['signature'], p.signature);
    expect(
      DateTime.parse(sent['timestamp']! as String),
      DateTime.parse(p.timestamp),
    );
    expect(pending.pending, isNull);

    // Never twice: again in this run, at a sign-in, and at the next start.
    await c.read(authProvider.notifier).sendPendingSignOut();
    await c
        .read(authProvider.notifier)
        .requestEmail(SignInFixtures.advancedEmail);
    await run(baseUrl: server.baseUri.toString());
    expect(server.lateSignOuts, hasLength(1));
  });

  test('concurrent sends share one request', () async {
    await signOutOffline();
    final c = await run(baseUrl: offline);
    final auth = c.read(authProvider.notifier);
    expect(
      identical(auth.sendPendingSignOut(), auth.sendPendingSignOut()),
      isTrue,
    );
    await auth.sendPendingSignOut();
  });

  test('a 5xx keeps it for the next connection; a 4xx drops it', () async {
    await signOutOffline();
    server.lateSignOutDown = true;
    await run(baseUrl: server.baseUri.toString());
    expect(server.lateSignOuts, isNotEmpty);
    expect(pending.pending, isNotNull);

    // Refused (the platform no longer knows the session): dropped.
    server.lateSignOutDown = false;
    pending.pending = PendingSignOut(
      deviceId: device,
      refreshToken: SignInFixtures.revokedRefreshToken,
      timestamp: pending.pending!.timestamp,
      signature: pending.pending!.signature,
    );
    final before = server.lateSignOuts.length;
    await run(baseUrl: server.baseUri.toString());
    expect(server.lateSignOuts, hasLength(before + 1));
    expect(pending.pending, isNull);
  });

  test('dropped unsent after 30 days', () async {
    await signOutOffline();
    now = now.add(const Duration(days: 31));
    await run(baseUrl: server.baseUri.toString());
    expect(server.lateSignOuts, isEmpty);
    expect(pending.pending, isNull);
  });

  test('a sign-out that reached the platform keeps nothing', () async {
    final c = await run(baseUrl: server.baseUri.toString());
    final auth = c.read(authProvider.notifier);
    await auth.requestEmail(SignInFixtures.advancedEmail);
    await auth.completeWithCode(SignInFixtures.code);
    expect(c.read(authProvider), isA<SignedIn>());
    await auth.signOut();
    expect(c.read(authProvider), isA<NotSignedIn>());
    expect(pending.pending, isNull);
    expect(keys.signed.where((m) => m.startsWith('sign-out.')), isEmpty);
  });
}
