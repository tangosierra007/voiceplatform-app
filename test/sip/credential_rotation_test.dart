// Q356-1 (TJ, 22 Nov): the app keeps its SIP account on the phone for up to
// 7 days. A normal start registers with the kept account and makes no
// `POST /devices/me/sip-credentials` (each POST rotates the password and
// drops the device's contacts); a new one is asked for only when none is
// kept, the kept one is refused (401 or 403), or it is 7 days old. Sign-out
// wipes the kept account before it returns.
//
// The native store (CredentialStore.kt, Android Keystore) is stood in for by
// [_KeepingEngine]: like the real engine, every register() with fresh
// credentials keeps the account and its issue time, and unregister() clears
// it. No test reads, prints or compares a password.
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
import 'package:voiceplatform_app/engine/kept_account.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart';
import '../../tool/mock_server/server.dart';
import '../support/call_fakes.dart';
import '../support/fakes.dart';

/// Keeps what register() was given, as the native side does.
class _KeepingEngine extends FakeCallEngine {
  _KeepingEngine() : super(registerAfter: Duration.zero);

  SipAccount? _kept;
  DateTime? keptAt;
  int freshRegisters = 0;
  int keptRegisters = 0;
  var _viaKept = false;

  bool get hasKept => _kept != null;

  @override
  Future<void> register(SipAccount account) {
    if (!_viaKept) {
      _kept = account;
      keptAt = DateTime.now();
      freshRegisters++;
    }
    return super.register(account);
  }

  Future<bool> registerKept(PushParams? push) async {
    final k = _kept;
    if (k == null) return false;
    keptRegisters++;
    _viaKept = true;
    try {
      await register(k);
    } finally {
      _viaKept = false;
    }
    return true;
  }

  @override
  Future<void> unregister() {
    _kept = null;
    keptAt = null;
    return super.unregister();
  }

  void forget() {
    _kept = null;
    keptAt = null;
  }
}

class _Kept implements KeptSipAccount {
  _Kept(this.engine);
  final _KeepingEngine engine;
  int wipes = 0;

  @override
  Future<DateTime?> issuedAt() async => engine.hasKept ? engine.keptAt : null;

  @override
  Future<bool> register({PushParams? push}) => engine.registerKept(push);

  @override
  Future<void> wipe() async {
    wipes++;
    engine.forget();
  }
}

void main() {
  late MockServer server;
  late SharedPreferences sp;
  late MemorySessionStore store;
  late _KeepingEngine engine;
  late _Kept kept;
  late StreamController<void> resumes;

  setUp(() async {
    HttpOverrides.global = null;
    // Each test its own server: the QR sign-in token works once.
    server = await MockServer.start(port: 0);
    addTearDown(server.close);
    SharedPreferences.setMockInitialValues({});
    sp = await SharedPreferences.getInstance();
    store = MemorySessionStore();
    engine = _KeepingEngine();
    kept = _Kept(engine);
    resumes = StreamController<void>.broadcast();
    addTearDown(resumes.close);
    addTearDown(engine.dispose);
  });

  /// One run of the app: a new container on the same phone (session store,
  /// settings and the engine's kept account survive).
  ProviderContainer appRun() {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(store),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        callEngineProvider.overrideWithValue(engine),
        keptSipAccountProvider.overrideWithValue(kept),
        pushTokensProvider.overrideWithValue(null),
        micPermissionProvider.overrideWithValue(FakeMic()),
        appResumesProvider.overrideWithValue(resumes.stream),
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
    return c;
  }

  Future<void> settle() async {
    await pumpEventQueue(times: 50);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await pumpEventQueue(times: 50);
  }

  /// First run: QR sign-in, nothing kept yet, so one POST.
  Future<ProviderContainer> signIn() async {
    final c = appRun();
    await pumpEventQueue();
    await c.read(authProvider.notifier).completeWithQr(SignInFixtures.qrToken);
    await settle();
    expect(engine.registrationState, RegistrationState.ok);
    expect(
      server.sipCredentialPosts,
      1,
      reason: 'nothing kept on a first sign-in',
    );
    expect(engine.hasKept, isTrue);
    return c;
  }

  /// The app is closed (its container goes) and started again.
  Future<ProviderContainer> restart(ProviderContainer before) async {
    before.dispose();
    final c = appRun();
    await settle();
    expect(c.read(authProvider), isA<SignedIn>());
    return c;
  }

  test('no rotation on a normal start', () async {
    final first = await signIn();
    final issued = engine.keptAt;
    final c = await restart(first);

    expect(
      server.sipCredentialPosts,
      1,
      reason: 'no POST: the kept account registers',
    );
    expect(engine.keptRegisters, 1);
    expect(engine.freshRegisters, 1);
    expect(engine.registrationState, RegistrationState.ok);
    expect(engine.keptAt, issued, reason: 'the 7 days still run from the POST');
    expect(engine.registeredAs, 'mock-202-pixel8@sip.demo-co.example');

    // A resume while registered, well inside the 7 days: nothing new.
    resumes.add(null);
    await settle();
    expect(server.sipCredentialPosts, 1);
    expect(c.read(authProvider), isA<SignedIn>());
  });

  test('rotates when the kept account is refused (401)', () async {
    final first = await signIn();
    engine.failNextRegistration(
      RegistrationFailure.badCredentials,
      sipCode: 401,
    );
    await restart(first);

    expect(engine.keptRegisters, 1, reason: 'the kept account was tried first');
    expect(
      server.sipCredentialPosts,
      2,
      reason: 'refused: a new password, once',
    );
    expect(engine.freshRegisters, 2);
    expect(engine.registrationState, RegistrationState.ok);
  });

  test(
    'rotates when the kept account is refused (403, a removed device)',
    () async {
      final first = await signIn();
      engine.failNextRegistration(RegistrationFailure.forbidden, sipCode: 403);
      await restart(first);

      expect(server.sipCredentialPosts, 2);
      expect(engine.registrationState, RegistrationState.ok);
    },
  );

  test('a refused fresh password is not asked for again in a loop', () async {
    final first = await signIn();
    engine.forget();
    engine.failNextRegistration(RegistrationFailure.forbidden, sipCode: 403);
    await restart(first);

    expect(
      server.sipCredentialPosts,
      2,
      reason: 'nothing kept: one POST, refused, no retry',
    );
    expect(engine.registrationState, RegistrationState.failed);
  });

  test('rotates when it is 7 days old', () async {
    final first = await signIn();
    engine.keptAt = DateTime.now().subtract(keptAccountMaxAge);
    await restart(first);

    expect(engine.keptRegisters, 0, reason: '7 days old: not used');
    expect(server.sipCredentialPosts, 2);
    expect(engine.registrationState, RegistrationState.ok);
    expect(
      DateTime.now().difference(engine.keptAt!),
      lessThan(const Duration(minutes: 1)),
    );
  });

  test('a day short of 7 days still registers with the kept account', () async {
    final first = await signIn();
    engine.keptAt = DateTime.now().subtract(const Duration(days: 6));
    await restart(first);

    expect(engine.keptRegisters, 1);
    expect(server.sipCredentialPosts, 1);
  });

  test(
    'a resume once the account in use turns 7 days old asks for a new one',
    () async {
      final first = await signIn();
      // Two seconds short of 7 days at this start, past them by the resume.
      engine.keptAt = DateTime.now().subtract(
        keptAccountMaxAge - const Duration(seconds: 2),
      );
      await restart(first);
      expect(engine.keptRegisters, 1);
      expect(server.sipCredentialPosts, 1);

      await Future<void>.delayed(const Duration(milliseconds: 2500));
      resumes.add(null);
      await settle();
      expect(server.sipCredentialPosts, 2);
      expect(engine.registrationState, RegistrationState.ok);
    },
  );

  test('sign-out wipes the kept account', () async {
    final c = await signIn();
    expect(engine.hasKept, isTrue);

    await c.read(authProvider.notifier).signOut();
    // Gone by the time the sign-out call returns, not later.
    expect(kept.wipes, 1);
    expect(engine.hasKept, isFalse);
    expect(await kept.issuedAt(), isNull);
    await settle();
    expect(c.read(authProvider), isA<NotSignedIn>());
  });

  group('keptAccountTooOld', () {
    final now = DateTime.utc(2026, 11, 23, 1);
    test('none kept', () => expect(keptAccountTooOld(null, now), isTrue));
    test('a minute old', () {
      expect(
        keptAccountTooOld(now.subtract(const Duration(minutes: 1)), now),
        isFalse,
      );
    });
    test('a second short of 7 days', () {
      expect(
        keptAccountTooOld(
          now.subtract(keptAccountMaxAge - const Duration(seconds: 1)),
          now,
        ),
        isFalse,
      );
    });
    test(
      'exactly 7 days',
      () => expect(
        keptAccountTooOld(now.subtract(keptAccountMaxAge), now),
        isTrue,
      ),
    );
    test('ahead of the clock', () {
      expect(
        keptAccountTooOld(now.add(const Duration(minutes: 5)), now),
        isTrue,
      );
    });
  });

  group('refusedCredentials', () {
    test('401 and 403 count; a network failure does not', () {
      expect(
        refusedCredentials(
          const RegistrationEvent(RegistrationState.failed, sipCode: 401),
        ),
        isTrue,
      );
      expect(
        refusedCredentials(
          const RegistrationEvent(
            RegistrationState.failed,
            failure: RegistrationFailure.forbidden,
          ),
        ),
        isTrue,
      );
      expect(
        refusedCredentials(
          const RegistrationEvent(
            RegistrationState.failed,
            failure: RegistrationFailure.network,
          ),
        ),
        isFalse,
      );
      expect(
        refusedCredentials(
          const RegistrationEvent(RegistrationState.ok, sipCode: 200),
        ),
        isFalse,
      );
    });
  });
}
