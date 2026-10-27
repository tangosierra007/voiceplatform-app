// Sign-in, licence gating, refresh and the version gate, end to end against
// the mock server (real HTTP on a local socket), with a fake device key and
// an in-memory session store.
import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/auth/version.dart';
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

  late ProviderContainer c;
  late MemorySessionStore store;
  late FakeDeviceKeys keys;

  Future<ProviderContainer> make({String version = '1.0.0'}) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    store = MemorySessionStore();
    keys = FakeDeviceKeys();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(store),
        deviceKeysProvider.overrideWithValue(keys),
        clockProvider.overrideWithValue(clock),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: server.baseUri.toString(),
            platform: 'android',
            appVersion: version,
            deviceModel: 'Pixel 8',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Let the controller read the (empty) store.
    container.read(authProvider);
    await pumpEventQueue();
    return container;
  }

  setUp(() async {
    now = DateTime.now();
    c = await make();
  });

  AuthController auth() => c.read(authProvider.notifier);

  Future<SignInFailure> failure(Future<void> f) async {
    try {
      await f;
    } on SignInFailure catch (e) {
      return e;
    }
    fail('expected a SignInFailure');
  }

  test('starts signed out with an empty store', () {
    expect(c.read(authProvider), isA<NotSignedIn>());
  });

  group('email and code', () {
    test(
      'the secret is 32 random bytes, kept in memory, and the code signs in',
      () async {
        await auth().requestEmail(SignInFixtures.advancedEmail);
        final p = c.read(pendingSignInProvider)!;
        expect(base64Url.decode(base64Url.normalize(p.secret)), hasLength(32));
        expect(p.resendAt.difference(now), const Duration(seconds: 60));
        expect(p.toString(), isNot(contains(p.secret)));

        await auth().completeWithCode(SignInFixtures.code);
        expect(c.read(authProvider), isA<SignedIn>());
        expect(c.read(accessTokenProvider), isNotNull);
        expect(c.read(pendingSignInProvider), isNull, reason: 'secret dropped');
        expect(store.session!.deviceId, uid(0x6, 1));
        expect(
          store.session.toString(),
          isNot(contains(store.session!.refreshToken)),
        );
      },
    );

    test(
      'an unknown email gets the same 202, and no code works for it',
      () async {
        await auth().requestEmail('nobody@democo.example');
        expect(c.read(pendingSignInProvider), isNotNull);
        final e = await failure(auth().completeWithCode(SignInFixtures.code));
        expect(e.code, 'invalid_code');
        expect(c.read(authProvider), isA<NotSignedIn>());
      },
    );

    test('five wrong codes lock the request', () async {
      await auth().requestEmail(SignInFixtures.advancedEmail);
      for (var i = 4; i >= 1; i--) {
        final e = await failure(auth().completeWithCode('000000'));
        expect(e.code, 'invalid_code');
        expect(e.message, contains('$i'));
      }
      final locked = await failure(auth().completeWithCode('000000'));
      expect(locked.code, 'request_locked');
      final after = await failure(auth().completeWithCode(SignInFixtures.code));
      expect(after.code, 'request_locked');
    });

    test('a code older than 10 minutes has expired', () async {
      await auth().requestEmail(SignInFixtures.advancedEmail);
      now = now.add(const Duration(minutes: 10, seconds: 1));
      final e = await failure(auth().completeWithCode(SignInFixtures.code));
      expect(e.code, 'code_expired');
    });

    test(
      'Send again waits for resendAfterSeconds, then restarts the timer',
      () async {
        await auth().requestEmail(SignInFixtures.advancedEmail);
        final early = await failure(auth().resend());
        expect(early.code, 'rate_limited');
        now = now.add(const Duration(seconds: 61));
        await auth().resend();
        expect(
          c.read(pendingSignInProvider)!.resendAt,
          now.add(const Duration(seconds: 60)),
        );
      },
    );

    test('device_limit says so', () async {
      await auth().requestEmail(SignInFixtures.deviceLimitEmail);
      final e = await failure(auth().completeWithCode(SignInFixtures.code));
      expect(e.code, 'device_limit');
      expect(e.message, contains('Sign out a device first'));
      expect(c.read(authProvider), isA<NotSignedIn>());
    });
  });

  group('App Link', () {
    test('completes with this phone\'s request', () async {
      await auth().requestEmail(SignInFixtures.advancedEmail);
      final id = c.read(pendingSignInProvider)!.requestId;
      await auth().completeWithLink(id, SignInFixtures.linkToken);
      expect(c.read(authProvider), isA<SignedIn>());
    });

    test(
      'a link for a request this phone did not make never completes',
      () async {
        final e = await failure(
          auth().completeWithLink(uid(0x9, 1), SignInFixtures.linkToken),
        );
        expect(e.message, SignInFailure.notThisPhone);
        final s = c.read(authProvider) as NotSignedIn;
        expect(
          s.notice,
          'This link only signs in the phone that asked for it.',
        );
      },
    );
  });

  group('QR', () {
    test('signs in once; the same QR again is used', () async {
      await auth().completeWithQr(SignInFixtures.qrToken);
      expect(c.read(authProvider), isA<SignedIn>());
      await auth().signOutLocally();
      final e = await failure(auth().completeWithQr(SignInFixtures.qrToken));
      expect(e.code, 'qr_used');
    });

    test('an unknown QR has expired', () async {
      final e = await failure(auth().completeWithQr('nope'));
      expect(e.code, 'qr_expired');
    });
  });

  group('Basic (APP3)', () {
    test(
      'AppBasic with the extension; Ask my admin sends the request',
      () async {
        await auth().requestEmail(SignInFixtures.basicEmail);
        await failure(auth().completeWithCode(SignInFixtures.code));
        final s = c.read(authProvider) as LicenceRefused;
        expect(s.refusal.extensionValue, '204');
        expect(s.refusal.extensionName, 'Warehouse');
        await auth().askAdminToUpgrade();
        auth().useDifferentEmail();
        expect(c.read(authProvider), isA<NotSignedIn>());
        expect(c.read(pendingSignInProvider), isNull);
      },
    );

    test('a QR for a Basic extension too', () async {
      await failure(auth().completeWithQr(SignInFixtures.qrBasicToken));
      expect(c.read(authProvider), isA<LicenceRefused>());
    });
  });

  group('refresh', () {
    Future<void> signIn() async {
      await auth().requestEmail(SignInFixtures.advancedEmail);
      await auth().completeWithCode(SignInFixtures.code);
    }

    test(
      'signs deviceId.refreshToken.timestamp with the device key and rotates',
      () async {
        await signIn();
        final before = store.session!.refreshToken;
        final access = c.read(accessTokenProvider);
        expect(await auth().refresh(), isTrue);
        final signed = keys.signed.single.split('.');
        expect(signed[0], uid(0x6, 1));
        expect(signed[1], before);
        expect(DateTime.parse(signed.sublist(2).join('.')).isUtc, isTrue);
        expect(store.session!.refreshToken, isNot(before));
        expect(c.read(accessTokenProvider), isNot(access));
      },
    );

    test(
      'reusing an old refresh token signs this phone out and clears it',
      () async {
        await signIn();
        final old = store.session!;
        expect(await auth().refresh(), isTrue);
        await store.write(old);
        expect(await auth().refresh(), isFalse);
        expect(c.read(authProvider), isA<NotSignedIn>());
        expect(store.session, isNull);
        expect(c.read(accessTokenProvider), isNull);
        expect(keys.deletes, 1);
      },
    );

    test('device_revoked: storage cleared, back to sign-in', () async {
      await store.write(
        StoredSession(
          deviceId: uid(0x6, 1),
          refreshToken: SignInFixtures.revokedRefreshToken,
        ),
      );
      expect(await auth().refresh(), isFalse);
      expect(c.read(authProvider), isA<NotSignedIn>());
      expect(store.session, isNull);
    });

    test('moved to Basic at refresh: AppBasic', () async {
      await store.write(
        StoredSession(
          deviceId: uid(0x6, 1),
          refreshToken: SignInFixtures.basicRefreshToken,
        ),
      );
      expect(await auth().refresh(), isFalse);
      expect(c.read(authProvider), isA<LicenceRefused>());
    });

    test('a 401 on an API call refreshes once and retries', () async {
      await signIn();
      now = now.add(const Duration(minutes: 16));
      final me = await c.read(appApiProvider).me.getMe();
      expect(me.name, 'Ava Nguyen');
      expect(keys.signed, hasLength(1));
    });

    test('a stored session restores signed in at start', () async {
      await signIn();
      final saved = store.session!;
      final c2 = await make();
      await store.write(saved);
      c2.invalidate(authProvider);
      c2.read(authProvider);
      await pumpEventQueue();
      expect(c2.read(authProvider), isA<SignedIn>());
    });
  });

  group('version gate (APP7)', () {
    test('below the minimum: /config sets AppUpdate', () async {
      final old = await make(version: '0.9.0');
      await old.read(appConfigProvider.notifier).check();
      expect(old.read(updateRequiredProvider)?.minimumVersion, '1.0.0');
    });

    test('any 426 sets AppUpdate', () async {
      final old = await make(version: '0.9.0');
      await expectLater(old.read(appApiProvider).me.getMe(), throwsA(anything));
      expect(old.read(updateRequiredProvider), isNotNull);
    });

    test('between minimum and recommended: the banner, once a day', () async {
      await c.read(appConfigProvider.notifier).check();
      expect(c.read(updateRequiredProvider), isNull);
      expect(c.read(updateBannerProvider), isTrue);
      await c.read(updateBannerProvider.notifier).dismiss();
      c.invalidate(updateBannerProvider);
      expect(c.read(updateBannerProvider), isFalse);
      now = now.add(const Duration(days: 1));
      c.invalidate(updateBannerProvider);
      expect(c.read(updateBannerProvider), isTrue);
    });

    test('at or above recommended: no banner', () async {
      final current = await make(version: '1.0.2');
      await current.read(appConfigProvider.notifier).check();
      expect(current.read(updateBannerProvider), isFalse);
    });
  });
}
