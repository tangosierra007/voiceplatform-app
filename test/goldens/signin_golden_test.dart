// Goldens for getting in at 390 x 844 (2x), light and dark, set up as the
// artboards show them: AppSignIn with Ava's address, AppCode with 4819 typed
// and 0:42 to wait, AppBasic for 204 Warehouse, AppUpdate at 1.0.1 and
// AppEmergency over the keypad. Side by side with the artboards in
// test/goldens/compare/signin_side_by_side.png.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/emergency/emergency.dart';
import 'package:voiceplatform_app/nav/routes.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_screen.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _t0 = DateTime.utc(2026, 10, 27, 0, 0, 0);

GoRouter _router(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
        .read(routerProvider);

Future<void> _shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile(name));

void main() {
  setUpAll(loadAppFonts);

  for (final (mode, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('AppSignIn $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(auth: const NotSignedIn(), theme: pref),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ava@democo.example');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _shot(tester, 'signin_$mode.png');
    });

    testWidgets('AppCode $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          auth: const NotSignedIn(),
          theme: pref,
          clock: () => _t0,
          pending: PendingSignIn(
            email: 'ava@democo.example',
            requestId: 'r1',
            secret: 's',
            resendAt: _t0.add(const Duration(seconds: 42)),
            expiresAt: _t0.add(const Duration(minutes: 10)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _router(tester).go(Routes.signInCode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), '4819');
      await tester.pump();
      await _shot(tester, 'code_$mode.png');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('AppBasic $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          auth: const LicenceRefused(warehouseRefusal),
          theme: pref,
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, 'basic_$mode.png');
    });

    testWidgets('AppUpdate $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          updateRequired: configWithMinimum('1.0.2'),
          appVersion: '1.0.1',
          theme: pref,
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, 'update_$mode.png');
    });

    testWidgets('AppEmergency $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(await appUnderTest(theme: pref));
      await tester.pumpAndSettle();
      // 000 typed on the keypad, as the artboard shows behind the sheet.
      final keypad = tester.element(find.byType(KeypadScreen));
      ProviderScope.containerOf(keypad)
          .read(dialledProvider.notifier)
          .set('000');
      await tester.pump();
      showEmergencySheet(keypad, '000');
      await tester.pumpAndSettle();
      await _shot(tester, 'emergency_$mode.png');
    });
  }
}
