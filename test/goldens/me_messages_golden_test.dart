// Goldens for Messages, Thread, Me and AppSignedOut at 390 x 844 (2x), as
// AppMessages, AppThread and AppMe (light and dark) and AppSignedOut show
// them, at 3:40 pm on Tuesday 27 October in Melbourne.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/nav/routes.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

Future<void> _shot(WidgetTester t, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile(name));

void main() {
  setUpAll(loadAppFonts);

  for (final (mode, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('AppMessages $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(theme: pref, clock: () => _now),
      );
      await _settle(tester);
      await tester.tap(_tab('Messages'));
      await _settle(tester);
      await _shot(tester, 'messages_$mode.png');
    });

    testWidgets('AppThread $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          theme: pref,
          clock: () => _now,
          api: FakeApi({
            'POST /messages/threads/${fx.threads.first['id']}/read': (_) =>
                null,
          }),
        ),
      );
      await _settle(tester);
      await tester.tap(_tab('Messages'));
      await _settle(tester);
      await tester.tap(find.text('Olivia Chen'));
      await _settle(tester);
      await _shot(tester, 'thread_$mode.png');
    });

    testWidgets('AppMe $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(theme: pref, clock: () => _now, appVersion: '1.0.3'),
      );
      await _settle(tester);
      await tester.tap(_tab('Me'));
      await _settle(tester);
      await _shot(tester, 'me_$mode.png');
    });
  }

  testWidgets('AppSignedOut light', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      await appUnderTest(
        theme: ThemePreference.light,
        clock: () => _now,
        authController: ScriptedAuth(
          SignedOutRemotely(
            SignedOut.fromJson({
              'error': 'device_revoked',
              'message': "You've been signed out",
              'revokedBy': 'Priya Shah, your admin',
              'revokedAt': '2026-10-27T04:12:00Z',
              'extension': '202',
              'support': fx.support,
            }),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      Routes.signedOut,
    );
    await _shot(tester, 'signed_out_light.png');
  });
}
