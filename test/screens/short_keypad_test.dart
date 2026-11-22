// The Keypad on a short window (FU56, Q309-4, task 401): one control row
// (Back to call or Offline, the number, Delete, More), status and caller ID
// behind More, the 12 keys and the call button always in view with no
// scroll, the emergency note kept, 000 still going to AppEmergency; the
// thresholds pinned to the normal layout's measured height, and the normal
// layouts unchanged above them.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/emergency/emergency.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_screen.dart';
import 'package:voiceplatform_app/shell/layout.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);
const _note = "For 000, 112 or 106 the phone's own dialler opens.";
const _offlineNote =
    "For 000, use your phone's own dialler.\nIt works without the app.";

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'test-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
);

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

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Finder _key(String d) {
  final label = switch (d) {
    '*' => 'Star',
    '#' => 'Hash',
    _ => d,
  };
  final re = RegExp('^${RegExp.escape(label)}( |\$|,)');
  return find
      .byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            re.hasMatch(w.properties.label ?? ''),
      )
      .first;
}

Future<void> _type(WidgetTester t, String digits) async {
  for (final d in digits.split('')) {
    await t.tap(_key(d));
    await t.pump();
  }
}

Future<_SpyEngine> _app(
  WidgetTester tester, {
  ThemePreference theme = ThemePreference.light,
  bool offline = false,
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
      offline: offline,
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

final _more = find.bySemanticsLabel('More');

/// The keypad's own box: the window less the status bar (and tab bar).
Rect _keypad(WidgetTester t) => t.getRect(find.byType(KeypadScreen));

/// Every key and the call button inside the keypad's box, at least 48 px,
/// with nothing scrolling.
void _allInView(WidgetTester t) {
  final box = _keypad(t);
  for (final d in [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '*',
    '0',
    '#',
  ]) {
    final r = t.getRect(_key(d));
    expect(
      box.contains(r.topLeft) && box.contains(r.bottomRight),
      isTrue,
      reason: 'key $d at $r, keypad $box',
    );
    expect(r.shortestSide, greaterThanOrEqualTo(48), reason: 'key $d');
  }
  final call = t.getRect(
    find.bySemanticsLabel(RegExp(r'^Call($|, unavailable)')),
  );
  expect(
    box.contains(call.topLeft) && box.contains(call.bottomRight),
    isTrue,
    reason: 'call at $call, keypad $box',
  );
  expect(call.shortestSide, greaterThanOrEqualTo(48));
  expect(
    find.descendant(
      of: find.byType(KeypadScreen),
      matching: find.byType(SingleChildScrollView),
    ),
    findsNothing,
    reason: 'the short layout never scrolls',
  );
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(loadAppFonts);

  group('the thresholds hold the normal layout (layout.dart)', () {
    // Where the normal layout's call button (or note) ends, at a window tall
    // enough for it, against the threshold that keeps it: if the layout
    // grows past it, this fails.
    for (final (w, wide) in [(360.0, false), (390.0, false), (884.0, true)]) {
      for (final state in ['online', 'offline', 'in a call']) {
        for (final text in [1.0, 1.15, 1.3, 1.45, 1.5, 2.0]) {
          // Offline from 150 % is always short (the next test).
          if (state == 'offline' && text >= 1.5) continue;
          testWidgets('${w.toInt()} dp, $state, ${(text * 100).round()} %', (
            tester,
          ) async {
            _window(tester, Size(w, 1600), text: text);
            final e = await _app(tester, offline: state == 'offline');
            if (state == 'in a call') {
              await tester.runAsync(
                () async => e.simulateIncoming(remoteNumber: '+61491570737'),
              );
              await _settle(tester);
              await tester.tap(find.bySemanticsLabel('Answer'));
              await _settle(tester);
              await tester.tap(find.bySemanticsLabel('Add call'));
              await _settle(tester);
              expect(
                find.bySemanticsLabel(RegExp('Back to the call')),
                findsOneWidget,
              );
            }
            final pane = tester.renderObject<RenderBox>(
              find
                  .descendant(
                    of: find.byType(KeypadScreen),
                    matching: find.byType(IntrinsicHeight),
                  )
                  .first,
            );
            // Less the 12 px under the call button (or note).
            final ends = pane.getMinIntrinsicHeight(pane.size.width) - 12;
            expect(
              ends,
              lessThanOrEqualTo(
                keypadShortBelow(
                  textScale: text,
                  note: wide,
                  offline: state == 'offline',
                  inCall: state == 'in a call',
                ),
              ),
            );
            await _end(tester, e);
          });
        }
      }
    }

    testWidgets('offline from 150 %: short at any height (the banner alone '
        'outgrows most screens)', (tester) async {
      _window(tester, const Size(884, 1600), text: 1.5);
      final e = await _app(tester, offline: true);
      expect(_more, findsOneWidget);
      expect(find.text(_offlineNote), findsOneWidget);
      _allInView(tester);
      await _end(tester, e);
    });
  });

  group('short windows', () {
    for (final size in [
      const Size(797, 443), // A3 folded landscape (8" emulator)
      const Size(797, 411), // Fold emulator cover, landscape
      const Size(797, 400),
      const Size(390, 443), // a phone-width short window (split screen)
    ]) {
      for (final text in [1.0, 2.0]) {
        testWidgets('${size.width.toInt()} x ${size.height.toInt()} at '
            '${(text * 100).round()} %: 12 keys and Call in view, one row, '
            'More', (tester) async {
          _window(tester, size, text: text);
          final e = await _app(tester);
          expect(_more, findsOneWidget);
          await _type(tester, '0491');
          await _settle(tester);
          _allInView(tester);
          // The row: the number and Delete; status and caller ID behind More.
          expect(find.bySemanticsLabel('Delete'), findsOneWidget);
          expect(find.bySemanticsLabel(RegExp('^Status: ')), findsNothing);
          expect(
            find.bySemanticsLabel(RegExp('Change caller ID')),
            findsNothing,
          );
          final wide = size.width >= wideLayoutMinWidth;
          if (wide) {
            final note = tester.getRect(find.text(_note));
            expect(
              _keypad(tester).contains(note.bottomCenter),
              isTrue,
              reason: 'the emergency note stays in view',
            );
          }
          await _end(tester, e);
        });
      }
    }

    testWidgets('More: status and caller ID, each reachable, 48 px rows', (
      tester,
    ) async {
      _window(tester, const Size(797, 443));
      final e = await _app(tester);
      await tester.tap(_more);
      await _settle(tester);
      final status = find.bySemanticsLabel('Status: Available');
      final callerId = find.bySemanticsLabel(
        RegExp(r'^Calls show .*\. Change caller ID$'),
      );
      expect(status, findsOneWidget);
      expect(callerId, findsOneWidget);
      expect(tester.getSize(status).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(callerId).height, greaterThanOrEqualTo(48));
      // Status opens the status sheet.
      await tester.tap(status);
      await _settle(tester);
      expect(find.text('Do not disturb'), findsOneWidget);
      expect(
        find.text('Your desk phone shows the same status.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Do not disturb'));
      await _settle(tester);
      // Caller ID opens the picker.
      await tester.tap(_more);
      await _settle(tester);
      expect(find.bySemanticsLabel('Status: Do not disturb'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('Change caller ID')));
      await _settle(tester);
      expect(find.byType(ListTile), findsWidgets);
      expect(
        find.byIcon(Icons.check),
        findsOneWidget,
        reason: 'the picked one',
      );
      await _end(tester, e);
    });

    testWidgets('000 at 443 dp still goes to AppEmergency, never the engine', (
      tester,
    ) async {
      _window(tester, const Size(797, 443), text: 2);
      final e = await _app(tester);
      await _type(tester, '000');
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Call'));
      await _settle(tester);
      expect(find.byType(EmergencySheet), findsOneWidget);
      expect(e.called, isEmpty);
      await _end(tester, e);
    });

    testWidgets('Delete takes a digit, holding it clears', (tester) async {
      _window(tester, const Size(797, 443));
      final e = await _app(tester);
      await _type(tester, '206');
      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(KeypadScreen)),
      );
      expect(c.read(dialledProvider), '20');
      await tester.longPress(find.bySemanticsLabel('Delete'));
      await tester.pump();
      expect(c.read(dialledProvider), '');
      await tester.tap(_key('0'));
      await tester.pump();
      await tester.longPress(_key('0'));
      await tester.pump();
      expect(c.read(dialledProvider), '0+');
      await _end(tester, e);
    });

    testWidgets('offline: the Offline chip, the 000 text, the banner behind '
        'More, keys and call off', (tester) async {
      _window(tester, const Size(797, 443), text: 2);
      final e = await _app(tester, offline: true);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text(_offlineNote), findsOneWidget);
      _allInView(tester);
      expect(
        find.bySemanticsLabel('Call, unavailable while offline'),
        findsOneWidget,
      );
      await tester.tap(_key('5'));
      await tester.pump();
      expect(e.called, isEmpty);
      await tester.tap(_more);
      await _settle(tester);
      expect(find.text('No internet on this phone'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Status: ')), findsNothing);
      await _end(tester, e);
    });

    testWidgets('during a call (Add call): Back to call in the row', (
      tester,
    ) async {
      // The call screen is set up unfolded, then the phone folds to the
      // short window on the Keypad.
      _window(tester, const Size(797, 1030));
      final e = await _app(tester);
      await tester.runAsync(
        () async => e.simulateIncoming(remoteNumber: '+61491570737'),
      );
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Add call'));
      await _settle(tester);
      tester.view.physicalSize = const Size(797, 443) * 2;
      await _settle(tester);
      expect(find.byType(KeypadScreen), findsOneWidget);
      final back = find.bySemanticsLabel(
        RegExp(r' · on (hold|a call)\. Back to the call$'),
      );
      expect(back, findsOneWidget);
      expect(_more, findsOneWidget);
      _allInView(tester);
      await tester.tap(back);
      await _settle(tester);
      expect(find.byType(KeypadScreen), findsNothing);
      await _end(tester, e);
    });
  });

  group('above the thresholds, as built', () {
    for (final (size, text) in [
      (phoneSize, 1.0),
      (phoneSize, 1.3),
      (const Size(884, 1030), 1.0),
      (const Size(884, 1030), 2.0),
    ]) {
      testWidgets('${size.width.toInt()} x ${size.height.toInt()} at '
          '${(text * 100).round()} %: chips, no More', (tester) async {
        _window(tester, size, text: text);
        final e = await _app(tester);
        expect(_more, findsNothing);
        expect(find.bySemanticsLabel('Status: Available'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Change caller ID')),
          findsOneWidget,
        );
        await _end(tester, e);
      });
    }

    testWidgets('the artboard phone at 200 %: short, so Call is in view', (
      tester,
    ) async {
      _window(tester, phoneSize, text: 2);
      final e = await _app(tester);
      expect(_more, findsOneWidget);
      _allInView(tester);
      // Behind More the caller ID line is whole, never cut.
      await tester.tap(_more);
      await _settle(tester);
      final line = find.textContaining('Calls show ');
      expect(line, findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.descendant(of: line, matching: find.byType(RichText)),
            )
            .didExceedMaxLines,
        isFalse,
      );
      await _end(tester, e);
    });
  });
}
