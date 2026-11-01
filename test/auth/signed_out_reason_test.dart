// A 401 from refresh: only `device_revoked` is a revocation and shows
// AppSignedOut (saying who only when the API names someone). Everything
// else (`refresh_invalid`, the clock message, a 401 with no usable body)
// blames no one: AppSignIn with "Please sign in again."
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/screens/signin/signed_out_screen.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/fake_api.dart';
import '../support/fakes.dart';

// Local times, so the line reads the same in any time zone (CI runs in UTC).
final _now = DateTime(2026, 10, 27, 16);

void main() {
  late MemorySessionStore store;

  /// Signed in from a stored session; `POST /auth/refresh` answers [answer].
  Future<ProviderContainer> make(Object? Function(SeenRequest) answer) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    store = MemorySessionStore()
      ..session = const StoredSession(deviceId: 'd1', refreshToken: 'r1');
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        sessionStoreProvider.overrideWithValue(store),
        deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
        clockProvider.overrideWithValue(() => _now),
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9/app/v1'))
            ..httpClientAdapter = FakeApi({'POST /auth/refresh': answer}),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(authProvider);
    await pumpEventQueue();
    // _restore signs in from the store and refreshes once by itself.
    return c;
  }

  void expectCleared(ProviderContainer c) {
    expect(store.session, isNull);
    expect(c.read(accessTokenProvider), isNull);
  }

  test('device_revoked with revokedBy and revokedAt: AppSignedOut says who '
      'and when', () async {
    final c = await make(
      (_) => (
        401,
        {
          'error': 'device_revoked',
          'message': "You've been signed out",
          'revokedBy': 'Priya Shah, your admin',
          'revokedAt': DateTime(2026, 10, 27, 15, 12).toUtc().toIso8601String(),
          'extension': '202',
          'support': fx.support,
        },
      ),
    );
    final s = c.read(authProvider);
    expect(s, isA<SignedOutRemotely>());
    expect(
      signedOutLine((s as SignedOutRemotely).info, _now),
      'Priya Shah, your admin, signed this phone out at 3:12 pm today. '
      'This usually happens when a phone is replaced or lost.',
    );
    expectCleared(c);
  });

  test('device_revoked without revokedBy or revokedAt: AppSignedOut, '
      'nobody blamed', () async {
    final c = await make(
      (_) => (
        401,
        {
          'error': 'device_revoked',
          'message': "You've been signed out",
          'extension': '202',
        },
      ),
    );
    final s = c.read(authProvider);
    expect(s, isA<SignedOutRemotely>());
    final line = signedOutLine((s as SignedOutRemotely).info, _now);
    expect(
      line,
      'This phone was signed out. '
      'This usually happens when a phone is replaced or lost.',
    );
    expect(line, isNot(contains('admin')));
    expect(
      line,
      isNot(contains(' at ')),
      reason: 'no time the API did not send',
    );
    expectCleared(c);
  });

  test('device_revoked with revokedAt but no revokedBy: the time, nobody '
      'blamed', () async {
    final c = await make(
      (_) => (
        401,
        {
          'error': 'device_revoked',
          'message': "You've been signed out",
          'revokedAt': DateTime(2026, 10, 27, 15, 12).toUtc().toIso8601String(),
        },
      ),
    );
    final s = c.read(authProvider) as SignedOutRemotely;
    expect(
      signedOutLine(s.info, _now),
      'This phone was signed out at 3:12 pm today. '
      'This usually happens when a phone is replaced or lost.',
    );
    expectCleared(c);
  });

  group('signed out by themselves (revokedBy "you")', () {
    SignedOut info({String? by, DateTime? at}) => SignedOut(
      error: SignedOutError.deviceRevoked,
      message: "You've been signed out",
      revokedBy: by,
      revokedAt: at?.toUtc(),
    );

    test('with a time', () async {
      final c = await make(
        (_) => (
          401,
          {
            'error': 'device_revoked',
            'message': "You've been signed out",
            'revokedBy': 'you',
            'revokedAt': DateTime(
              2026,
              10,
              27,
              15,
              12,
            ).toUtc().toIso8601String(),
            'support': fx.support,
          },
        ),
      );
      final s = c.read(authProvider) as SignedOutRemotely;
      expect(
        signedOutLine(s.info, _now),
        'You signed this phone out at 3:12 pm today.',
      );
      expect(isSelfRevocation(s.info), isTrue);
      expectCleared(c);
    });

    test('without a time: none made up', () {
      expect(
        signedOutLine(info(by: 'you'), _now),
        'You signed this phone out.',
      );
    });

    test('yesterday and older read as the other cases', () {
      expect(
        signedOutLine(info(by: 'you', at: DateTime(2026, 10, 26, 9, 5)), _now),
        'You signed this phone out at 9:05 am yesterday.',
      );
    });

    test('a named admin and nobody named are unchanged', () {
      final at = DateTime(2026, 10, 27, 15, 12);
      expect(
        signedOutLine(info(by: 'Priya Shah, your admin', at: at), _now),
        'Priya Shah, your admin, signed this phone out at 3:12 pm today. '
        'This usually happens when a phone is replaced or lost.',
      );
      expect(
        signedOutLine(info(at: at), _now),
        'This phone was signed out at 3:12 pm today. '
        'This usually happens when a phone is replaced or lost.',
      );
      expect(isSelfRevocation(info(by: 'Priya Shah, your admin')), isFalse);
      expect(isSelfRevocation(info(by: 'You')), isFalse, reason: 'exactly');
    });
  });

  test('named or not, the time and day read the same', () {
    for (final at in [
      DateTime(2026, 10, 27, 15, 12), // today
      DateTime(2026, 10, 26, 9, 5), // yesterday
      DateTime(2026, 10, 14, 11, 0), // older
    ]) {
      SignedOut info(String? who) => SignedOut(
        error: SignedOutError.deviceRevoked,
        message: "You've been signed out",
        revokedBy: who,
        revokedAt: at.toUtc(),
      );
      final named = signedOutLine(info('Priya Shah, your admin'), _now);
      final nobody = signedOutLine(info(null), _now);
      // Everything from " out" on: " out at 3:12 pm today. This usually ..."
      String tail(String s) => s.substring(s.indexOf(' out'));
      expect(tail(nobody), tail(named), reason: '$at');
      expect(nobody, startsWith('This phone was signed out '));
      expect(tail(nobody), isNot(startsWith(' out.')), reason: 'has a time');
    }
  });

  test('refresh_invalid: AppSignIn, "Please sign in again."', () async {
    final c = await make(
      (_) => (401, {'error': 'refresh_invalid', 'message': 'Sign in again'}),
    );
    final s = c.read(authProvider);
    expect(s, isA<NotSignedIn>());
    expect((s as NotSignedIn).notice, 'Please sign in again.');
    expectCleared(c);
  });

  test('refresh_invalid for the clock: the API\'s message too', () async {
    final c = await make(
      (_) => (
        401,
        {
          'error': 'refresh_invalid',
          'message': "Check this phone's date and time",
        },
      ),
    );
    final s = c.read(authProvider) as NotSignedIn;
    expect(s.notice, "Please sign in again. Check this phone's date and time.");
    expectCleared(c);
  });

  for (final (name, body) in [
    ('no body', null),
    ('a body that is not SignedOut', {'error': 'unauthorized'}),
    (
      'an error code this build does not know',
      {'error': 'something_new', 'message': 'Sign in again'},
    ),
  ]) {
    test('a 401 with $name: AppSignIn, "Please sign in again."', () async {
      final c = await make((_) => (401, body));
      final s = c.read(authProvider);
      expect(s, isA<NotSignedIn>());
      expect((s as NotSignedIn).notice, 'Please sign in again.');
      expectCleared(c);
    });
  }

  test('the notice: the generic message adds nothing', () {
    SignedOut info(String m) =>
        SignedOut(error: SignedOutError.refreshInvalid, message: m);
    expect(SignInFailure.signInAgainNotice(null), 'Please sign in again.');
    for (final m in [
      'Sign in again',
      'Sign in again.',
      ' sign in again ',
      '',
    ]) {
      expect(
        SignInFailure.signInAgainNotice(info(m)),
        'Please sign in again.',
        reason: m,
      );
    }
    expect(
      SignInFailure.signInAgainNotice(
        info("Check this phone's date and time."),
      ),
      "Please sign in again. Check this phone's date and time.",
    );
  });
}
