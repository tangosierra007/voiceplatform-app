// Recents at 800 dp and wider (FoldRecents): the calls on the left, the one
// picked beside them; on the phone, the call's own page; and the pick
// following fold and unfold.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/recents/recent_detail.dart';
import 'package:voiceplatform_app/shell/layout.dart';
import 'package:voiceplatform_app/shell/list_detail.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);
const _unfolded = Size(884, 1030);
const _phone = Size(390, 844);

void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pumpAndSettle();
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  await _settle(tester);
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

Finder _button(String label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      w.properties.label == label,
);

String? _detailTitle(WidgetTester tester) {
  final d = find.byType(RecentDetail);
  if (d.evaluate().isEmpty) return null;
  return tester.widget<RecentDetail>(d).entry.name;
}

FakeApi _api() => FakeApi({
  for (final v in fx.voicemails)
    'POST /voicemail/messages/${v['id']}/media-url': (_) => {
      'url': '/app/v1/media/token-${v['id']}',
      'expiresAt': '2026-10-27T00:15:00.000Z',
    },
});

HistoryEntry _h(
  String outcome, {
  String direction = 'incoming',
  int? seconds,
  String? answeredBy,
  int day = 27,
}) => HistoryEntry.fromJson({
  'id': '$outcome$day',
  // Local times, so the text reads the same in any time zone (CI: UTC).
  'at': DateTime(2026, 10, day, 14, 4).toUtc().toIso8601String(),
  'direction': direction,
  'outcome': outcome,
  'number': '+61355501987',
  'durationSeconds': ?seconds,
  'answeredBy': ?answeredBy,
});

void main() {
  setUpAll(loadAppFonts);

  group('wording', () {
    test('each call in "Recent calls with"', () {
      expect(callWithLine(_h('voicemail')), 'Missed, left voicemail');
      expect(callWithLine(_h('missed')), 'Missed');
      expect(
        callWithLine(_h('answered', seconds: 185), myFirstName: 'Ava'),
        'Answered by Ava, 3:05',
      );
      expect(
        callWithLine(
          _h('answered_elsewhere', answeredBy: 'Mia on her desk phone'),
        ),
        'Answered by Mia on her desk phone',
      );
      expect(
        callWithLine(_h('answered', direction: 'outgoing', seconds: 97)),
        'You called, 1:37',
      );
      expect(
        callWithLine(_h('missed', direction: 'outgoing')),
        'You called, no answer',
      );
    });

    test('last answered: the newest answered call only, or nothing', () {
      final now = DateTime(2026, 10, 27, 16);
      expect(
        lastAnsweredLine(
          [_h('missed'), _h('answered', seconds: 185, day: 24)],
          now,
          myName: 'Ava Nguyen',
        ),
        'Last answered by Ava Nguyen, Sat 2:04 pm',
      );
      expect(lastAnsweredLine([_h('missed'), _h('voicemail')], now), isNull);
    });
  });

  testWidgets('unfolded: list and the newest call beside it', (tester) async {
    _window(tester, _unfolded);
    await tester.pumpWidget(await appUnderTest(clock: () => _now, api: _api()));
    await _settle(tester);
    await _openTab(tester, 'Recents');
    expect(find.byType(ListDetailLayout), findsOneWidget);
    expect(_detailTitle(tester), 'Westgate Supplies');
    expect(find.text('Mine only'), findsOneWidget, reason: 'TJ, 2 Nov');
    expect(find.text('Recent calls with Westgate Supplies'), findsOneWidget);
    expect(find.textContaining('in the phonebook'), findsOneWidget);
    expect(_button('Play'), findsOneWidget, reason: 'the voicemail left');
    await tester.tap(find.text('Jordan Price').first);
    await _settle(tester);
    expect(_detailTitle(tester), 'Jordan Price');
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone details, unfold, fold, Back: the pick follows', (
    tester,
  ) async {
    _window(tester, _phone);
    await tester.pumpWidget(await appUnderTest(clock: () => _now, api: _api()));
    await _settle(tester);
    await _openTab(tester, 'Recents');
    await tester.tap(_button('Details for Jordan Price'));
    await _settle(tester);
    expect(_detailTitle(tester), 'Jordan Price');
    expect(find.byType(ListDetailLayout), findsNothing);

    await _resize(tester, _unfolded);
    expect(find.byType(ListDetailLayout), findsOneWidget);
    expect(_detailTitle(tester), 'Jordan Price');

    await _resize(tester, _phone);
    expect(find.byType(ListDetailLayout), findsNothing);
    expect(_detailTitle(tester), 'Jordan Price');

    await tester.tap(_button('Back to Recents'));
    await _settle(tester);
    expect(find.byType(RecentDetail), findsNothing);
    await _resize(tester, _unfolded);
    expect(_detailTitle(tester), 'Westgate Supplies', reason: 'the newest');
    await _resize(tester, _phone);
    expect(find.byType(RecentDetail), findsNothing, reason: 'not picked');
  });

  // The split (TJ, 2 Nov): list and detail from 680 dp, the list 280 to 360
  // dp wide; the proof widths at 200% text, light and dark.
  for (final w in [679.0, 680.0, 690.0, 744.0, 852.0, 884.0]) {
    for (final theme in [ThemePreference.light, ThemePreference.dark]) {
      testWidgets('${w.toInt()} dp, ${theme.name}, 200% text: '
          '${w >= listDetailMinWidth ? 'list and detail' : 'the list, then '
                    'the call'}; nothing past its box', (tester) async {
        _window(tester, Size(w, 1030));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          await appUnderTest(theme: theme, clock: () => _now, api: _api()),
        );
        await _settle(tester);
        await _openTab(tester, 'Recents');
        expect(find.byType(VpNavRail), findsOneWidget);
        if (w >= listDetailMinWidth) {
          expect(find.byType(ListDetailLayout), findsOneWidget);
          final list = find
              .descendant(
                of: find.byType(ListDetailLayout),
                matching: find.byType(SizedBox),
              )
              .first;
          expect(tester.getSize(list).width, listPaneWidth(w - railWidth));
          expect(_detailTitle(tester), 'Westgate Supplies');
        } else {
          expect(find.byType(ListDetailLayout), findsNothing);
          expect(find.byType(RecentDetail), findsNothing);
          expect(find.text('Mine only'), findsOneWidget);
          await tester.tap(_button('Details for Jordan Price'));
          await _settle(tester);
          expect(_detailTitle(tester), 'Jordan Price');
        }
        if (w >= listDetailMinWidth) {
          expect(find.text('Mine only'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        // The voicemail filter at the same size.
        if (w >= listDetailMinWidth) {
          await tester.ensureVisible(find.text('Voicemail 2').first);
          await tester.tap(find.text('Voicemail 2').first);
          await _settle(tester);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final size in [
    _phone,
    const Size(360, 800),
    const Size(412, 915),
    const Size(368, 904),
  ]) {
    testWidgets('phone ${size.width.toInt()} x ${size.height.toInt()}: the '
        'phone Recents, unchanged', (tester) async {
      _window(tester, size);
      await tester.pumpWidget(
        await appUnderTest(clock: () => _now, api: _api()),
      );
      await _settle(tester);
      await _openTab(tester, 'Recents');
      expect(find.byType(VpTabBar), findsOneWidget);
      expect(find.byType(ListDetailLayout), findsNothing);
      expect(find.byType(RecentDetail), findsNothing);
      expect(find.text('Mine only'), findsOneWidget);
      expect(_button('Details for Jordan Price'), findsOneWidget);
    });
  }

  testWidgets('Galaxy Z Fold5 shape: unfold to 690 with a call open, fold '
      'back to the cover', (tester) async {
    _window(tester, const Size(368, 904));
    await tester.pumpWidget(await appUnderTest(clock: () => _now, api: _api()));
    await _settle(tester);
    await _openTab(tester, 'Recents');
    await tester.tap(_button('Details for Chris Doyle'));
    await _settle(tester);
    await _resize(tester, const Size(690, 1030));
    expect(find.byType(ListDetailLayout), findsOneWidget);
    expect(_detailTitle(tester), 'Chris Doyle');
    await _resize(tester, const Size(368, 904));
    expect(find.byType(ListDetailLayout), findsNothing);
    expect(_detailTitle(tester), 'Chris Doyle');
  });

  testWidgets('screen reader: rows are buttons with selected state', (
    tester,
  ) async {
    _window(tester, _unfolded);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(await appUnderTest(clock: () => _now, api: _api()));
    await _settle(tester);
    await _openTab(tester, 'Recents');
    final row = find.bySemanticsLabel(
      RegExp(r'^Westgate Supplies, .*Details$'),
    );
    expect(
      tester.getSemantics(row),
      matchesSemantics(
        label: tester.getSemantics(row).label,
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(find.bySemanticsLabel(RegExp('Calls show')), findsWidgets);
    handle.dispose();
  });

  group('calls with this number (GET /history?number=)', () {
    Map<String, Object?> entry(String id, String number, int seconds) => {
      'id': id,
      'at': DateTime(2026, 10, 20, 9, 30).toUtc().toIso8601String(),
      'direction': 'outgoing',
      'outcome': 'answered',
      'number': number,
      'durationSeconds': seconds,
    };

    Future<void> open(WidgetTester tester, FakeApi api) async {
      _window(tester, _unfolded);
      await tester.pumpWidget(
        await appUnderTest(clock: () => _now, api: api, accessToken: 'tok-1'),
      );
      await _settle(tester);
      await _openTab(tester, 'Recents');
    }

    testWidgets('the server\'s calls, older ones included; anything with '
        'another number left out', (tester) async {
      String? asked;
      final api = _api()
        ..routes['GET /history'] = (r) {
          asked = r.uri.queryParameters['number'];
          return {
            'items': [
              fx.history.first,
              entry('older', '+61355501987', 120),
              // A server that doesn't filter yet sends everything.
              entry('other', '+61491570737', 599),
            ],
            'counts': {'missed': 2, 'voicemail': 2},
          };
        };
      await open(tester, api);
      expect(asked, '+61355501987');
      expect(find.text('You called, 2:00'), findsOneWidget);
      expect(find.text('You called, 9:59'), findsNothing);
    });

    testWidgets('the request fails: the calls Recents has stand in', (
      tester,
    ) async {
      final api = _api()
        ..routes['GET /history'] = (_) => (500, {'error': 'internal'});
      await open(tester, api);
      expect(find.text('Recent calls with Westgate Supplies'), findsOneWidget);
      expect(find.text('Missed, left voicemail'), findsOneWidget);
    });
  });
}
