// The keypad and the call in the wide layout (FoldKeypad, FoldInCall; TJ,
// 2 Nov): the space-based split, the matches beside the keypad, a tap that
// fills the number but never calls, the half-typed number across fold and
// unfold, the call's details beside it; 200% text at every proof width, and
// the phone sizes unchanged.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/calls/numbers.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/calls/call_details_panel.dart';
import 'package:voiceplatform_app/screens/calls/in_call_screen.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_matches.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_screen.dart';
import 'package:voiceplatform_app/shell/layout.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);
const _note = "For 000, 112 or 106 the phone's own dialler opens.";

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'test-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
);

/// Records the calls the keypad places.
class _SpyEngine extends FakeCallEngine {
  _SpyEngine()
    : super(
        outgoing: OutgoingScript.manual,
        registerAfter: Duration.zero,
        clock: () => _now.subtract(const Duration(seconds: 84)),
      );
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

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  await _settle(tester);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _type(WidgetTester t, String digits) async {
  for (final d in digits.split('')) {
    final re = RegExp('^${RegExp.escape(d)}( |\$|,)');
    await t.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.button == true &&
                re.hasMatch(w.properties.label ?? ''),
          )
          .first,
    );
    await t.pump();
  }
}

Future<_SpyEngine> _app(
  WidgetTester tester, {
  ThemePreference theme = ThemePreference.light,
}) async {
  final e = _SpyEngine();
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
  await tester.pumpAndSettle();
  return e;
}

Future<void> _end(WidgetTester t, FakeCallEngine e) async {
  await t.pumpWidget(const SizedBox());
  await e.dispose();
}

String _dialled(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(KeypadScreen)))
        .read(dialledProvider);

/// The matches pane beside the keypad, if shown.
final _pane = find.byType(KeypadMatchesPane);

/// A fixture time as the screens show it in this machine's time zone (CI runs
/// in UTC; the fixtures are Melbourne times): "11:04 am".
String _local(Map<String, Object?> h) =>
    clockTime(DateTime.parse(h['at']! as String).toLocal());

/// "Today 10:42 am" in Melbourne; "Yesterday 11:42 pm" in UTC.
String _lastCall(Map<String, Object?> h) {
  final a = DateTime.parse(h['at']! as String).toLocal();
  final n = _now.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(a.year, a.month, a.day);
  return '${day == today ? 'Today' : 'Yesterday'} ${clockTime(a)}';
}

Finder _inPane(String text) =>
    find.descendant(of: _pane, matching: find.text(text, findRichText: true));

void main() {
  setUpAll(loadAppFonts);

  group('the split (layout.dart)', () {
    // Window widths in dp; the keypad sits next to the 80 dp rail.
    final keypad = {
      679.0: null,
      680.0: (phone: 360.0, side: 240.0),
      690.0: (phone: 370.0, side: 240.0),
      744.0: (phone: 420.0, side: 244.0),
      852.0: (phone: 420.0, side: 352.0),
      884.0: (phone: 420.0, side: 384.0),
    };
    for (final MapEntry(key: w, value: want) in keypad.entries) {
      test('keypad at $w dp: $want', () {
        expect(phonePaneSplit(w - railWidth), want);
      });
    }
    test('the keypad splits from the same window as list and detail', () {
      expect(phonePaneSplit(listDetailMinWidth - railWidth), isNotNull);
      expect(phonePaneSplit(listDetailMinWidth - 1 - railWidth), isNull);
    });
    test('a call has no rail: it splits from 600 dp', () {
      expect(phonePaneSplit(599), isNull);
      expect(phonePaneSplit(600), (phone: 360.0, side: 240.0));
      expect(phonePaneSplit(884), (phone: 420.0, side: 464.0));
    });
  });

  group('matches', () {
    final colleagues = [
      for (final c in fx.colleagues)
        Colleague.fromJson({
          'userId': fx.uid(0xa, c['n']! as int),
          'name': c['name'],
          'initials': c['initials'],
          'extension': '${c['n']}',
          'team': c['team'],
          'mobile': c['mobile'],
          'presence': {'extension': '${c['n']}', 'presence': c['presence']},
        }),
    ];
    final shared = [
      for (final s in fx.sharedContacts) SharedContact.fromJson(s),
    ];
    final history = [for (final h in fx.history) HistoryEntry.fromJson(h)];
    List<KeypadMatch> of(String typed) => keypadMatches(
      typed: typed,
      colleagues: colleagues,
      presence: const {},
      shared: shared,
      history: history,
      matcher: ContactMatcher(colleagues: colleagues, shared: shared),
      now: _now,
    );

    test('nothing typed: none', () => expect(of(''), isEmpty));

    test('0491: colleagues, the phonebook and recent calls, once each', () {
      final m = of('0491');
      expect(
        [for (final x in m) (x.name, x.source.tag)],
        [
          ('Priya Shah', 'Colleague'),
          ('Jordan Price', 'Phonebook'),
          ('Olivia Chen', 'Phonebook'),
          ('0491 570 110', 'Recent'),
          ('Chris Doyle', 'Recent'),
        ],
      );
      final jordan = m[1];
      expect(jordan.detail, 'Harbour Cafe · 0491 570 737');
      expect(jordan.number, '0491570737');
      expect(jordan.label, 'Jordan Price, Harbour Cafe');
      expect(m[0].detail, '302 · Free');
      expect(m[3].label, isNull, reason: 'the name would repeat the number');
      expect(m[4].detail, '0491 571 804 · incoming yesterday');
    });

    test('a number in the phonebook and Recents shows once, as Phonebook', () {
      final m = of('03 5550 1987');
      expect([for (final x in m) x.source], [KeypadMatchSource.phonebook]);
    });

    test('an extension: the colleague; ext and name on the box', () {
      final m = of('30');
      expect([for (final x in m) x.name], ['Priya Shah', 'Tom Walsh']);
      expect(m.first.source, KeypadMatchSource.colleague);
      final priya = m.firstWhere((x) => x.name == 'Priya Shah');
      expect(priya.number, '302');
      expect(priya.label, 'Priya Shah, ext 302');
    });

    test('a missed call reads "missed" with its time', () {
      final m = of('0355501987');
      expect(m, hasLength(1));
      final missed = keypadMatches(
        typed: '0355501987',
        colleagues: const [],
        presence: const {},
        shared: const [],
        history: history,
        matcher: ContactMatcher(),
        now: _now,
      ).single;
      // 11:04 am in Melbourne; read in the machine's own time zone.
      expect(missed.detail, '03 5550 1987 · missed ${_local(fx.history[0])}');
      expect(missed.source, KeypadMatchSource.recent);
    });

    test('numbers that start with the digits come first; private callers '
        'never match', () {
      // 3 starts extensions 302, 312 and 301, and is inside 03 5550 1987,
      // 0491 570 737 and 03 5550 1142.
      expect(
        [for (final x in of('3')) x.number],
        ['302', '312', '301', '0355501987', '0491570737', '0355501142'],
      );
      expect(of('anonymous'), isEmpty);
    });
  });

  testWidgets('884 dp, nothing typed: the colleagues free now, with presence', (
    tester,
  ) async {
    _window(tester, const Size(884, 1030));
    final e = await _app(tester);
    expect(_pane, findsOneWidget);
    expect(_inPane('Keypad'), findsOneWidget);
    expect(_inPane('3 FREE NOW'), findsOneWidget);
    for (final name in ['Mia Rossi', 'Priya Shah', 'Tom Walsh']) {
      expect(_inPane(name), findsOneWidget);
    }
    for (final name in ['Ava Nguyen', "Liam O'Brien", 'Sam Lee']) {
      expect(_inPane(name), findsNothing);
    }
    expect(find.text(_note), findsOneWidget);
    expect(find.text('Available'), findsWidgets, reason: 'the status chip');
    expect(find.textContaining('Calls show'), findsOneWidget);

    // A tap fills the extension and the name; it never calls.
    await tester.tap(_inPane('Priya Shah'));
    await _settle(tester);
    expect(_dialled(tester), '302');
    expect(find.text('Priya Shah, ext 302'), findsOneWidget);
    expect(e.called, isEmpty);
    await _end(tester, e);
  });

  testWidgets('884 dp, typing: matches; a tap fills it in; only Call calls', (
    tester,
  ) async {
    _window(tester, const Size(884, 1030));
    final e = await _app(tester);
    await _type(tester, '0491');
    await _settle(tester);
    expect(_inPane('Jordan Price'), findsOneWidget);
    expect(_inPane('Harbour Cafe · 0491 570 737'), findsOneWidget);
    expect(_inPane('Phonebook'), findsNWidgets(2));
    expect(_inPane('Colleague'), findsOneWidget);
    expect(_inPane('Recent'), findsNWidgets(2));

    await tester.tap(_inPane('Jordan Price'));
    await _settle(tester);
    expect(_dialled(tester), '0491570737');
    expect(find.text('0491 570 737'), findsWidgets);
    expect(find.text('Jordan Price, Harbour Cafe'), findsOneWidget);
    expect(e.called, isEmpty, reason: 'no one-tap calling');
    // The matches stay those for 0491, with Jordan marked.
    expect(_inPane('Olivia Chen'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Jordan Price, '))),
      isSemantics(isSelected: true),
    );
    // Another key: the matches follow the number again.
    await _type(tester, '1');
    await _settle(tester);
    expect(_inPane('Olivia Chen'), findsNothing);
    expect(_inPane('No one matches.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete'));
    await _settle(tester);
    expect(_inPane('Jordan Price'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Call'));
    await _settle(tester);
    expect(e.called, ['0491570737']);
    await _end(tester, e);
  });

  testWidgets('a recent caller the phone does not know keeps their name in '
      'the box, across a fold', (tester) async {
    _window(tester, const Size(884, 1030));
    final e = await _app(tester);
    await _type(tester, '0491571');
    await _settle(tester);
    await tester.tap(_inPane('Chris Doyle'));
    await _settle(tester);
    expect(find.text('Chris Doyle'), findsWidgets);
    await _resize(tester, phoneSize);
    expect(_pane, findsNothing);
    expect(_dialled(tester), '0491571804');
    expect(find.text('Chris Doyle'), findsOneWidget);
    // Change the number and the name goes.
    await tester.tap(find.bySemanticsLabel('Delete'));
    await _settle(tester);
    expect(find.text('Chris Doyle'), findsNothing);
    await _end(tester, e);
  });

  testWidgets('a half-typed number survives unfold and fold', (tester) async {
    _window(tester, phoneSize);
    final e = await _app(tester);
    await _type(tester, '04915');
    await _settle(tester);
    expect(_pane, findsNothing);
    await _resize(tester, const Size(884, 1030));
    expect(_pane, findsOneWidget);
    expect(_dialled(tester), '04915');
    expect(_inPane('Jordan Price'), findsOneWidget);
    await _type(tester, '70');
    await _settle(tester);
    await _resize(tester, phoneSize);
    expect(_dialled(tester), '0491570');
    // The Fold5's portrait shape, then folded again.
    await _resize(tester, const Size(690, 1030));
    expect(_pane, findsOneWidget);
    expect(_dialled(tester), '0491570');
    await _resize(tester, const Size(368, 904));
    expect(_dialled(tester), '0491570');
    await _end(tester, e);
  });

  for (final (w, split) in [
    (679.0, false),
    (680.0, true),
    (690.0, true),
    (744.0, true),
    (852.0, true),
    (884.0, true),
  ]) {
    for (final theme in [ThemePreference.light, ThemePreference.dark]) {
      testWidgets('${w.toInt()} dp, ${theme.name}, 200% text: '
          '${split ? 'beside its matches' : 'centred at phone width'}, '
          'nothing past its box', (tester) async {
        _window(tester, Size(w, 1030), text: 2);
        final e = await _app(tester, theme: theme);
        await _type(tester, '0491');
        await _settle(tester);
        expect(find.byType(VpNavRail), findsOneWidget);
        expect(_pane, split ? findsOneWidget : findsNothing);
        final keys = tester.getRect(find.bySemanticsLabel('Call'));
        final available = w - railWidth;
        if (split) {
          final s = phonePaneSplit(available)!;
          expect(tester.getSize(_pane).width, s.side);
          // The call button sits in the middle of the keypad's column.
          expect(keys.center.dx, closeTo(w - s.phone / 2, 1));
          expect(_inPane('Jordan Price'), findsOneWidget);
        } else {
          expect(keys.center.dx, closeTo(railWidth + available / 2, 1));
          expect(find.text('Jordan Price, Harbour Cafe'), findsNothing);
        }
        expect(find.text(_note), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _end(tester, e);
      });
    }
  }

  for (final size in [
    phoneSize,
    const Size(360, 800),
    const Size(412, 915),
    const Size(368, 904),
  ]) {
    testWidgets('phone ${size.width.toInt()} x ${size.height.toInt()}: the '
        'phone keypad, unchanged', (tester) async {
      _window(tester, size);
      final e = await _app(tester);
      await _type(tester, '0491570737');
      await _settle(tester);
      expect(find.byType(VpNavRail), findsNothing);
      expect(_pane, findsNothing);
      expect(find.text(_note), findsNothing);
      expect(find.text('Jordan Price, Harbour Cafe'), findsOneWidget);
      expect(
        tester.getRect(find.bySemanticsLabel('Call')).center.dx,
        closeTo(size.width / 2, 1),
      );
      await _end(tester, e);
    });
  }

  group('in call', () {
    Future<String> answer(WidgetTester tester, FakeCallEngine e) async {
      late String id;
      await tester.runAsync(
        () async => id = e.simulateIncoming(
          remoteNumber: '+61491570737',
          info: IncomingInfo(
            calledNumber: '+61355501201',
            calledLabel: 'Sales',
            repeatCount: 2,
            lastAnsweredBy: 'Mia Rossi',
            lastAnsweredAt: DateTime.utc(2026, 10, 26, 22, 15),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      return id;
    }

    testWidgets('884 dp: the call at phone width, its caller beside it; '
        'gaps said plainly', (tester) async {
      _window(tester, const Size(884, 1030));
      final e = await _app(tester);
      await answer(tester, e);
      expect(find.byType(InCallScreen), findsOneWidget);
      expect(find.byType(CallDetailsPanel), findsOneWidget);
      expect(find.byType(VpNavRail), findsNothing);
      expect(tester.getSize(find.byType(CallDetailsPanel)).width, 464);
      expect(find.text('2nd call this week'), findsOneWidget);
      expect(
        find.text(
          'Last answered by Mia Rossi, '
          '${whenShort(DateTime.utc(2026, 10, 26, 22, 15), _now)}',
        ),
        findsOneWidget,
      );
      expect(find.text('About Jordan'), findsOneWidget);
      expect(find.bySemanticsLabel('Phonebook: Harbour Cafe'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Last call: ${_lastCall(fx.history[1])}, 4:12'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Calls this month: $notShownYet'),
        findsOneWidget,
      );
      expect(find.text('None waiting from Jordan'), findsOneWidget);
      expect(find.bySemanticsLabel('Now: $notShownYet'), findsOneWidget);
      expect(find.bySemanticsLabel('Audio: Phone'), findsOneWidget);
      await tester.runAsync(() => e.setAudioRoute(AudioRoute.speaker));
      await _settle(tester);
      expect(find.bySemanticsLabel('Audio: Speaker'), findsOneWidget);
      // Nothing in the panel is a button.
      final buttons = find.descendant(
        of: find.byType(CallDetailsPanel),
        matching: find.byWidgetPredicate(
          (w) => w is InkWell || w is ButtonStyleButton,
        ),
      );
      expect(buttons, findsNothing);
      await _end(tester, e);
    });

    testWidgets('fold mid-call: the same call, the phone screen; and back', (
      tester,
    ) async {
      _window(tester, const Size(884, 1030));
      final e = await _app(tester);
      final id = await answer(tester, e);
      await _resize(tester, phoneSize);
      expect(find.byType(CallDetailsPanel), findsNothing);
      expect(tester.widget<InCallScreen>(find.byType(InCallScreen)).callId, id);
      expect(e.activeCalls.single.state, CallState.connected);
      await _resize(tester, const Size(690, 1030));
      expect(find.byType(CallDetailsPanel), findsOneWidget);
      await _end(tester, e);
    });

    for (final w in [600.0, 680.0, 690.0, 744.0, 852.0, 884.0]) {
      testWidgets('${w.toInt()} dp at 200% text: nothing past its box', (
        tester,
      ) async {
        _window(tester, Size(w, 1030), text: 2);
        final e = await _app(tester, theme: ThemePreference.dark);
        await answer(tester, e);
        expect(find.byType(CallDetailsPanel), findsOneWidget);
        expect(
          tester.getSize(find.byType(CallDetailsPanel)).width,
          phonePaneSplit(w)!.side,
        );
        expect(tester.takeException(), isNull);
        await _end(tester, e);
      });
    }

    testWidgets('an unknown number: about this caller, no phonebook row', (
      tester,
    ) async {
      _window(tester, const Size(884, 1030));
      final e = await _app(tester);
      await tester.runAsync(
        () async => e.simulateIncoming(remoteNumber: '+61491578888'),
      );
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      expect(find.text('About this caller'), findsOneWidget);
      expect(find.textContaining('Phonebook'), findsNothing);
      expect(find.textContaining('call this week'), findsNothing);
      expect(find.text('None waiting from this caller'), findsOneWidget);
      await _end(tester, e);
    });
  });
}
