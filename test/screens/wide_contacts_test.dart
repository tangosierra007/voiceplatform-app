// Contacts in windows that split (FoldContacts; TJ's space-based rule, 2
// Nov): the list on the left, the colleague picked beside it with presence,
// Call and Call mobile, their contact details and the calls with them. The
// proof widths at 200% text, light and dark; the phone sizes unchanged.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/contacts/colleague_detail.dart';
import 'package:voiceplatform_app/shell/layout.dart';
import 'package:voiceplatform_app/shell/list_detail.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);
const _unfolded = Size(884, 1030);
const _phone = Size(390, 844);

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'test-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
);

class _Spy extends FakeCallEngine {
  _Spy() : super(outgoing: OutgoingScript.manual, registerAfter: Duration.zero);
  final called = <String>[];

  @override
  Future<String> call(String number, {String? callerId}) {
    called.add(number);
    return super.call(number, callerId: callerId);
  }
}

void _window(WidgetTester tester, Size size, {double text = 1}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  await _settle(tester);
}

Future<_Spy> _open(
  WidgetTester tester, {
  ThemePreference theme = ThemePreference.light,
}) async {
  final e = _Spy();
  await e.start();
  await e.register(_account);
  await tester.pumpWidget(
    await appUnderTest(
      engine: e,
      theme: theme,
      clock: () => _now,
      api: FakeApi({}),
    ),
  );
  await _settle(tester);
  final rail = find.descendant(
    of: find.byType(VpNavRail),
    matching: find.text('Contacts'),
  );
  await tester.tap(
    rail.evaluate().isNotEmpty
        ? rail
        : find.descendant(
            of: find.byType(VpTabBar),
            matching: find.text('Contacts'),
          ),
  );
  await _settle(tester);
  return e;
}

Future<void> _end(WidgetTester t, FakeCallEngine e) async {
  await t.pumpWidget(const SizedBox());
  await e.dispose();
}

String? _shown(WidgetTester tester) {
  final d = find.byType(ColleagueDetail);
  if (d.evaluate().isEmpty) return null;
  return tester.widget<ColleagueDetail>(d).colleague.name;
}

/// A label and value pair in the detail, as read out ("Extension: 302").
Finder _kv(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Scrolls the list (not the filter chips) until [f] is built and in view.
Future<void> _reach(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
  f,
  200,
  scrollable: find
      .descendant(
        of: find.byType(ListDetailLayout),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first,
);

Finder _row(String name) => find.descendant(
  of: find.byType(ListDetailLayout),
  matching: find.text(name),
);

void main() {
  setUpAll(loadAppFonts);

  test('the calls with a colleague, in their words', () {
    HistoryEntry h(String direction, String outcome) => HistoryEntry.fromJson({
      'id': 'x',
      'at': '2026-10-27T00:00:00Z',
      'direction': direction,
      'outcome': outcome,
      'number': '302',
      'durationSeconds': 97,
    });
    expect(
      colleagueCallLine(h('outgoing', 'answered'), 'Priya'),
      'You called Priya, 1:37',
    );
    expect(
      colleagueCallLine(h('incoming', 'answered'), 'Priya'),
      'Priya called you, 1:37',
    );
    expect(colleagueCallLine(h('incoming', 'missed'), 'Priya'), 'Missed');
  });

  testWidgets('884 dp: the list and the first colleague other than you; '
      'picking Priya shows her', (tester) async {
    _window(tester, _unfolded);
    final e = await _open(tester);
    expect(find.byType(ListDetailLayout), findsOneWidget);
    expect(_shown(tester), 'Reception', reason: 'Ava is you');
    await tester.tap(_row('Priya Shah'));
    await _settle(tester);
    expect(_shown(tester), 'Priya Shah');
    final detail = find.byType(ColleagueDetail);
    Finder inDetail(Finder f) => find.descendant(of: detail, matching: f);
    expect(inDetail(find.text('Call 302')), findsOneWidget);
    expect(inDetail(find.text('Call mobile')), findsOneWidget);
    expect(inDetail(_kv('Extension: 302')), findsOneWidget);
    expect(inDetail(_kv('Mobile: 0491 570 156')), findsOneWidget);
    expect(inDetail(_kv('Teams: Accounts')), findsOneWidget);
    expect(inDetail(find.text('Calls with Priya')), findsOneWidget);
    expect(inDetail(find.text('You called Priya, 1:37')), findsOneWidget);
    expect(
      find.text('Send to voicemail'),
      findsNothing,
      reason: 'A5 is not in the contract: no dead button',
    );
    await tester.tap(inDetail(find.text('Call 302')));
    await _settle(tester);
    expect(e.called, ['302']);
    await _end(tester, e);
  });

  testWidgets('a team member picked on Teams shows; Phone contacts keeps the '
      'colleague beside it', (tester) async {
    _window(tester, _unfolded);
    final e = await _open(tester);
    await tester.tap(find.text('Teams'));
    await _settle(tester);
    await tester.tap(_row('Accounts'));
    await _settle(tester);
    await tester.tap(_row('Priya Shah'));
    await _settle(tester);
    expect(_shown(tester), 'Priya Shah');
    await tester.tap(find.text('Phone contacts'));
    await _settle(tester);
    expect(_shown(tester), 'Priya Shah');
    await _end(tester, e);
  });

  testWidgets('the pick follows fold and unfold', (tester) async {
    _window(tester, _unfolded);
    final e = await _open(tester);
    await tester.tap(_row('Mia Rossi'));
    await _settle(tester);
    await _resize(tester, _phone);
    expect(find.byType(ListDetailLayout), findsNothing);
    expect(find.byType(ColleagueDetail), findsNothing);
    await _resize(tester, const Size(690, 1030));
    expect(_shown(tester), 'Mia Rossi');
    await _end(tester, e);
  });

  for (final w in [679.0, 680.0, 690.0, 744.0, 852.0, 884.0]) {
    for (final theme in [ThemePreference.light, ThemePreference.dark]) {
      testWidgets('${w.toInt()} dp, ${theme.name}, 200% text: '
          '${w >= listDetailMinWidth ? 'list and detail' : 'the list'}; '
          'nothing past its box', (tester) async {
        _window(tester, Size(w, 1030), text: 2);
        final e = await _open(tester, theme: theme);
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
          await _reach(tester, _row('Priya Shah'));
          await tester.ensureVisible(_row('Priya Shah'));
          await tester.pumpAndSettle();
          await tester.tap(_row('Priya Shah'));
          await _settle(tester);
          expect(_shown(tester), 'Priya Shah');
        } else {
          expect(find.byType(ListDetailLayout), findsNothing);
          expect(find.byType(ColleagueDetail), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await _end(tester, e);
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
        'phone Contacts, unchanged', (tester) async {
      _window(tester, size);
      final e = await _open(tester);
      expect(find.byType(VpTabBar), findsOneWidget);
      expect(find.byType(ListDetailLayout), findsNothing);
      expect(find.byType(ColleagueDetail), findsNothing);
      expect(find.text('Priya Shah'), findsOneWidget);
      await _end(tester, e);
    });
  }
}
