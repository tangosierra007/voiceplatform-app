// FU56 (A3, 11 Nov): Recents at 690 dp, the voicemail wording, and the
// Contacts free count.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/features/recents/recents_format.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/screens/recents/recent_detail.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

void _window(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final rail = find.descendant(
    of: find.byType(VpNavRail),
    matching: find.text(label),
  );
  await tester.tap(
    rail.evaluate().isNotEmpty
        ? rail
        : find.descendant(
            of: find.byType(VpTabBar),
            matching: find.text(label),
          ),
  );
  await _settle(tester);
}

HistoryEntry _voicemail({String? voicemailId}) => HistoryEntry.fromJson({
  'id': 'h1',
  'at': '2026-10-27T03:04:00.000Z',
  'direction': 'incoming',
  'outcome': 'voicemail',
  'number': '+61355501987',
  'voicemailId': ?voicemailId,
});

void main() {
  setUpAll(loadAppFonts);

  group('Recents at 690 dp (a Fold5 unfolded)', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('the filters and the call beside them fit at ${scale}x', (
        tester,
      ) async {
        _window(tester, const Size(690, 880), scale);
        await tester.pumpWidget(await appUnderTest());
        await _settle(tester);
        await _openTab(tester, 'Recents');
        // An overflow would fail the test here (a RenderFlex error).
        expect(tester.takeException(), isNull);
        expect(find.byType(RecentDetail), findsOneWidget);
        // The filters scroll sideways rather than overflow.
        expect(find.text('Mine only', skipOffstage: false), findsOneWidget);
      });
    }
  });

  group('voicemail wording: "left voicemail" only when a message was kept', () {
    test('the Recents line', () {
      expect(
        historySubtitle(
          _voicemail(voicemailId: 'c0000000-0000-4000-8000-000000000001'),
        ),
        'Missed · left voicemail',
      );
      expect(historySubtitle(_voicemail()), 'Missed · went to voicemail');
    });

    test('"Recent calls with"', () {
      expect(
        callWithLine(
          _voicemail(voicemailId: 'c0000000-0000-4000-8000-000000000001'),
        ),
        'Missed, left voicemail',
      );
      expect(callWithLine(_voicemail()), 'Missed, went to voicemail');
    });
  });

  testWidgets(
    'Contacts: the free count is the colleagues shown free, never another extension',
    (tester) async {
      usePhone(tester);
      final events = StreamController<ServerEvent>.broadcast();
      final live = LiveEvents(
        connect: () => events.stream,
        poll: (_) async => (items: null, etag: null),
      );
      await tester.pumpWidget(
        await appUnderTest(clock: () => DateTime.utc(2026, 10, 27), live: live),
      );
      await _settle(tester);
      await _openTab(tester, 'Contacts');
      expect(find.text('22 COLLEAGUES · 3 FREE NOW'), findsOneWidget);
      // The snapshot carries every extension of the tenant, the user's own
      // and ones that aren't colleagues; only colleagues count.
      await tester.runAsync(() async {
        events.add(
          const ServerEvent('presence.snapshot', {
            'items': [
              {'extension': '299', 'presence': 'available'},
              {'extension': '206', 'presence': 'available'},
            ],
          }),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await _settle(tester);
      expect(find.text('22 COLLEAGUES · 3 FREE NOW'), findsOneWidget);
      await tester.runAsync(() async {
        events.add(
          const ServerEvent('presence', {
            'extension': '206',
            'presence': 'away',
          }),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await _settle(tester);
      expect(find.text('22 COLLEAGUES · 2 FREE NOW'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await live.dispose();
      await events.close();
    },
  );
}
