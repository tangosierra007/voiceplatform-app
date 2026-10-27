// Screen reader labels, 48 px tap targets and 200 % text on Messages,
// Thread, New message, Me and its pages, and AppSignedOut.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/engine/phone_extras.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/nav/routes.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

final _now = DateTime.utc(2026, 10, 27, 4, 40);

Future<void> _open(WidgetTester tester, String screen) async {
  usePhone(tester);
  await tester.pumpWidget(
    await appUnderTest(
      clock: () => _now,
      authController: screen == 'signedout'
          ? ScriptedAuth(
              SignedOutRemotely(
                SignedOut.fromJson({
                  'error': 'device_revoked',
                  'message': 'x',
                  'revokedBy': 'Priya Shah, your admin',
                  'revokedAt': '2026-10-27T04:12:00Z',
                  'extension': '202',
                  'support': fx.support,
                }),
              ),
            )
          : null,
      extras: FakeExtras(
        batteryStatus: const VpBatteryStatus(
          ignoringOptimizations: false,
          lateWakesLastWeek: 3,
          manufacturer: 'samsung',
        ),
      ),
      api: FakeApi({
        'POST /messages/threads/${fx.threads.first['id']}/read': (_) => null,
      }),
    ),
  );
  await _settle(tester);
  final router = ProviderScope.containerOf(
    tester.element(find.byType(Navigator).first),
  ).read(routerProvider);
  final path = switch (screen) {
    'messages' => Routes.messages,
    'thread' => '/thread/${fx.threads.first['id']}',
    'new' => '/new-message',
    'me' => Routes.me,
    'callsettings' => '/me/call-settings',
    'recordings' => '/me/recordings',
    'devices' => '/me/devices',
    _ => null,
  };
  if (path != null) {
    if (path.startsWith('/me/') || path == Routes.messages) {
      await tester.tap(
        find.descendant(
          of: find.byType(VpTabBar),
          matching: find.text(path == Routes.messages ? 'Messages' : 'Me'),
        ),
      );
      await _settle(tester);
    }
    if (path.startsWith('/me/') ||
        path.startsWith('/thread') ||
        path == '/new-message') {
      router.push(path);
    } else {
      router.go(path);
    }
  }
  await _settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  for (final screen in [
    'messages',
    'thread',
    'new',
    'me',
    'callsettings',
    'recordings',
    'devices',
    'signedout',
  ]) {
    testWidgets('$screen: labelled tap targets of 48 px', (tester) async {
      final h = tester.ensureSemantics();
      await _open(tester, screen);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      h.dispose();
    });

    testWidgets('$screen: 200 % text stays inside', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, screen);
      expect(tester.takeException(), isNull);
    });
  }
}
