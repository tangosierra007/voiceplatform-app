import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/version.dart';
import 'package:voiceplatform_app/screens/signin/basic_screen.dart';
import 'package:voiceplatform_app/screens/signin/code_screen.dart';
import 'package:voiceplatform_app/screens/signin/sign_in_screen.dart';
import 'package:voiceplatform_app/screens/signin/update_screen.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _t0 = DateTime.utc(2026, 10, 27, 0, 0, 0);

PendingSignIn _pending(DateTime now, {int resendIn = 42}) => PendingSignIn(
  email: 'ava@democo.example',
  requestId: 'r1',
  secret: 's',
  resendAt: now.add(Duration(seconds: resendIn)),
  expiresAt: now.add(const Duration(minutes: 10)),
);

/// Taps the email button and lets the code screen's route settle (the code
/// screen ticks each second, so pumpAndSettle would wait for the timer).
/// Visible text inside a RichText (semantics labels left out).
Finder _richText(String s) => find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.text.toPlainText(includeSemanticsLabels: false).contains(s),
);

Future<void> _toCode(WidgetTester tester) async {
  await tester.tap(find.text('Email me a sign-in link'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(loadAppFonts);

  group('AppSignIn', () {
    testWidgets('copy as the artboard', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(await appUnderTest(auth: const NotSignedIn()));
      await tester.pumpAndSettle();
      for (final s in [
        'Sign in with your work email',
        "We'll email you a link and a code. No password needed.",
        'Work email',
        'Email me a sign-in link',
        'or',
        'Scan the QR code instead',
        "The app works with an Advanced licence. Ask your admin if you're not sure which you have.",
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
    });

    testWidgets(
      'a bad address is refused on the phone, a good one asks for the code',
      (tester) async {
        usePhone(tester);
        final auth = ScriptedAuth(const NotSignedIn());
        await tester.pumpWidget(
          await appUnderTest(authController: auth, clock: () => _t0),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'ava');
        await tester.tap(find.text('Email me a sign-in link'));
        await tester.pumpAndSettle();
        expect(find.text('Enter your work email address.'), findsOneWidget);
        expect(auth.calls, isEmpty);

        await tester.enterText(find.byType(TextField), 'ava@democo.example');
        await tester.tap(find.text('Email me a sign-in link'));
        await tester.pumpAndSettle();
        expect(auth.calls, ['requestEmail']);
        expect(find.byType(CodeScreen), findsOneWidget);
        expect(find.text('Check your email'), findsOneWidget);
      },
    );

    testWidgets('a server message shows under the field', (tester) async {
      usePhone(tester);
      final auth = ScriptedAuth(
        const NotSignedIn(),
        script: (call, _) => throw const SignInFailure(SignInFailure.offline),
      );
      await tester.pumpWidget(await appUnderTest(authController: auth));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ava@democo.example');
      await _toCode(tester);
      expect(find.text(SignInFailure.offline), findsOneWidget);
    });

    testWidgets('a notice (forwarded link) shows', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          auth: const NotSignedIn(notice: SignInFailure.notThisPhone),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This link only signs in the phone that asked for it.'),
        findsOneWidget,
      );
    });

    testWidgets('the email field is labelled for screen readers', (
      tester,
    ) async {
      usePhone(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(await appUnderTest(auth: const NotSignedIn()));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Work email')), findsWidgets);
      expect(find.bySemanticsLabel('Email me a sign-in link'), findsOneWidget);
      expect(find.bySemanticsLabel('Scan the QR code instead'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      h.dispose();
    });
  });

  group('AppCode', () {
    testWidgets('timer counts down, then Send again', (tester) async {
      usePhone(tester);
      var now = _t0;
      final auth = ScriptedAuth(const NotSignedIn());
      await tester.pumpWidget(
        await appUnderTest(
          authController: auth,
          pending: _pending(_t0),
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      // Opened at /sign-in (email filled from the request); the email step
      // pushes the code screen.
      expect(find.byType(SignInScreen), findsOneWidget);
      await _toCode(tester);
      expect(_richText('Send again in 1:00'), findsOneWidget);
      expect(
        find.textContaining('ava@democo.example', findRichText: true),
        findsOneWidget,
      );

      now = _t0.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Send again'), findsOneWidget);
      await tester.tap(find.text('Send again'));
      await tester.pump();
      expect(auth.calls.last, 'resend');
      // Stop the screen's ticker.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('six digits submit by themselves; paste works; errors show', (
      tester,
    ) async {
      usePhone(tester);
      var fail = true;
      final auth = ScriptedAuth(
        const NotSignedIn(),
        script: (call, args) {
          if (call == 'completeWithCode' && fail) {
            fail = false;
            throw const SignInFailure(
              "That code isn't right. 4 tries left.",
              code: 'invalid_code',
            );
          }
        },
      );
      await tester.pumpWidget(
        await appUnderTest(authController: auth, clock: () => _t0),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ava@democo.example');
      await _toCode(tester);

      await tester.enterText(find.byType(TextField), '48 19 07');
      await tester.pump();
      await tester.pump();
      expect(auth.calls.last, 'completeWithCode');
      expect(find.text("That code isn't right. 4 tries left."), findsOneWidget);

      // Pasted with spaces: only the digits are kept.
      await tester.enterText(find.byType(TextField), '123 456');
      await tester.pump();
      await tester.pump();
      expect(auth.calls.where((c) => c == 'completeWithCode'), hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the field is one labelled one-time-code input', (
      tester,
    ) async {
      usePhone(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        await appUnderTest(
          authController: ScriptedAuth(const NotSignedIn()),
          clock: () => _t0,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ava@democo.example');
      await _toCode(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
      expect(field.keyboardType, TextInputType.number);
      expect(find.bySemanticsLabel(RegExp('6-digit code')), findsWidgets);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('AppBasic', () {
    testWidgets('names the extension; Ask my admin; Use a different email', (
      tester,
    ) async {
      usePhone(tester);
      final auth = ScriptedAuth(const LicenceRefused(warehouseRefusal));
      await tester.pumpWidget(await appUnderTest(authController: auth));
      await tester.pumpAndSettle();
      expect(find.byType(BasicScreen), findsOneWidget);
      expect(
        find.text(
          'Your extension, 204 Warehouse, is on Basic. Basic covers a desk phone with calls '
          'charged as they go. The mobile and desktop app comes with Advanced.',
        ),
        findsOneWidget,
      );
      expect(find.text('Your desk phone keeps working'), findsOneWidget);
      expect(find.text('Voicemail still arrives by email'), findsOneWidget);

      await tester.tap(find.text('Ask my admin to upgrade'));
      await tester.pumpAndSettle();
      expect(auth.calls, ['askAdminToUpgrade']);
      expect(find.textContaining("We've asked your admin"), findsOneWidget);

      await tester.tap(find.text('Use a different email'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('AppUpdate', () {
    testWidgets(
      'blocks everything; no back; Update now opens the Play listing',
      (tester) async {
        usePhone(tester);
        final phone = FakePhone();
        await tester.pumpWidget(
          await appUnderTest(
            updateRequired: configWithMinimum('1.0.2'),
            appVersion: '1.0.1',
            phone: phone,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(UpdateScreen), findsOneWidget);
        expect(find.byType(VpTabBar), findsNothing);
        expect(find.text('Update to keep calling'), findsOneWidget);
        expect(
          find.textContaining('This version (1.0.1) can no longer'),
          findsOneWidget,
        );
        expect(
          find.text("For emergencies, use your phone's dialler."),
          findsOneWidget,
        );

        final popped = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(popped, isTrue, reason: 'the back press is taken and ignored');
        expect(find.byType(UpdateScreen), findsOneWidget);

        await tester.tap(find.text('Update now'));
        await tester.pump();
        expect(phone.opened.single, contains('id=au.com.voiceplatform.app'));
      },
    );

    testWidgets('the recommended-version banner on the tabs, until Not now', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          config: configWithMinimum('1.0.0', recommended: '1.0.3'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A new version of the app is ready.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('A new version of the app is ready.'), findsNothing);
    });

    testWidgets('a banner dismissed today stays away', (tester) async {
      usePhone(tester);
      final today = DateTime.now();
      await tester.pumpWidget(
        await appUnderTest(
          config: configWithMinimum('1.0.0', recommended: '1.0.3'),
          prefs: {
            UpdateBannerNotifier.storageKey:
                '${today.year}-${today.month}-${today.day}',
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A new version of the app is ready.'), findsNothing);
    });
  });

  group('links', () {
    testWidgets('a forwarded link shows the notice on AppSignIn', (
      tester,
    ) async {
      usePhone(tester);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final auth = _LinkAuth(const NotSignedIn());
      await tester.pumpWidget(
        await appUnderTest(authController: auth, links: links.stream),
      );
      await tester.pumpAndSettle();
      links.add(
        Uri.parse('https://portal.voiceplatform.com.au/app/signin/other/tok'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This link only signs in the phone that asked for it.'),
        findsOneWidget,
      );
    });
  });

  group('200 % text stays inside the screen', () {
    for (final (name, make) in <(String, Future<Widget> Function())>[
      ('AppSignIn', () => appUnderTest(auth: const NotSignedIn())),
      (
        'AppBasic',
        () => appUnderTest(auth: const LicenceRefused(warehouseRefusal)),
      ),
      (
        'AppUpdate',
        () => appUnderTest(
          updateRequired: configWithMinimum('1.0.2'),
          appVersion: '1.0.1',
        ),
      ),
    ]) {
      testWidgets(name, (tester) async {
        usePhone(tester);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(await make());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('AppCode', (tester) async {
      usePhone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        await appUnderTest(
          authController: ScriptedAuth(const NotSignedIn()),
          clock: () => _t0,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ava@democo.example');
      await tester.ensureVisible(find.text('Email me a sign-in link'));
      await _toCode(tester);
      expect(find.byType(CodeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// Applies the real link rule (no pending request here).
class _LinkAuth extends ScriptedAuth {
  _LinkAuth(super.initial);

  @override
  Future<void> completeWithLink(String requestId, String linkToken) async {
    state = const NotSignedIn(notice: SignInFailure.notThisPhone);
    throw const SignInFailure(
      SignInFailure.notThisPhone,
      code: 'not_this_phone',
    );
  }
}
