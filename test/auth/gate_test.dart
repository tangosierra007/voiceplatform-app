import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/links.dart';
import 'package:voiceplatform_app/auth/version.dart';
import 'package:voiceplatform_app/nav/routes.dart';

import '../support/fakes.dart';

void main() {
  String? go(
    String at,
    AuthState auth, {
    bool update = false,
    bool pending = false,
  }) => gateRedirect(
    location: at,
    auth: auth,
    updateRequired: update,
    hasPendingEmail: pending,
  );

  const signedIn = SignedIn('d');
  const signedOut = NotSignedIn();
  const basic = LicenceRefused(warehouseRefusal);

  test(
    'below the minimum version, every route goes to AppUpdate and stays',
    () {
      for (final at in [
        Routes.keypad,
        Routes.signIn,
        Routes.signInCode,
        Routes.me,
        '/in-call/x',
      ]) {
        for (final a in [signedIn, signedOut, basic, const AuthStarting()]) {
          expect(go(at, a, update: true), Routes.update, reason: '$at $a');
        }
      }
      expect(go(Routes.update, signedIn, update: true), isNull);
    },
  );

  test('starting waits on the blank canvas', () {
    expect(go(Routes.keypad, const AuthStarting()), Routes.starting);
    expect(go(Routes.starting, const AuthStarting()), isNull);
  });

  test(
    'signed out: only the sign-in routes; the code screen needs a request',
    () {
      expect(go(Routes.keypad, signedOut), Routes.signIn);
      expect(go(Routes.starting, signedOut), Routes.signIn);
      expect(go(Routes.signIn, signedOut), isNull);
      expect(go(Routes.signInQr, signedOut), isNull);
      expect(go(Routes.signInCode, signedOut), Routes.signIn);
      expect(go(Routes.signInCode, signedOut, pending: true), isNull);
      expect(go(Routes.signInBasic, signedOut), Routes.signIn);
      expect(go(Routes.update, signedOut), Routes.starting);
    },
  );

  test('licence refused: AppBasic only', () {
    expect(go(Routes.signIn, basic), Routes.signInBasic);
    expect(go(Routes.keypad, basic), Routes.signInBasic);
    expect(go(Routes.signInBasic, basic), isNull);
  });

  test('signed in: sign-in routes go to Keypad; tabs and calls stay', () {
    expect(go(Routes.signIn, signedIn), Routes.keypad);
    expect(go(Routes.signInCode, signedIn), Routes.keypad);
    expect(go(Routes.starting, signedIn), Routes.keypad);
    expect(go(Routes.contacts, signedIn), isNull);
    expect(go('/incoming/x', signedIn), isNull);
  });

  test('versions compare as numbers', () {
    expect(compareVersions('1.0.10', '1.0.9'), 1);
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('0.9.9', '1.0.0'), -1);
    expect(compareVersions('1.0.2+7', '1.0.2'), 0);
    expect(compareVersions('1.1', '1.0.5'), 1);
  });

  group('links', () {
    test('the email link', () {
      final l = parseSignInLink(
        Uri.parse('https://portal.voiceplatform.com.au/app/signin/r-1/tok-2'),
      );
      expect(l, isA<EmailSignInLink>());
      final e = l! as EmailSignInLink;
      expect(e.requestId, 'r-1');
      expect(e.linkToken, 'tok-2');
    });

    test('the QR', () {
      expect(qrSignInToken('vpapp://signin/abc'), 'abc');
      expect(
        parseSignInLink(Uri.parse('vpapp://signin/abc')),
        isA<QrSignInLink>(),
      );
      expect(qrSignInToken('vpapp://other/abc'), isNull);
      expect(qrSignInToken('https://example.com/abc'), isNull);
      expect(qrSignInToken('vpapp://signin/'), isNull);
    });

    test('anything else is ignored', () {
      expect(
        parseSignInLink(
          Uri.parse('https://portal.voiceplatform.com.au/app/other/a/b'),
        ),
        isNull,
      );
      expect(parseSignInLink(Uri.parse('tel:000')), isNull);
    });
  });
}
