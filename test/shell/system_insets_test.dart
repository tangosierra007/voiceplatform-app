// Android's navigation bar over the app (TJ's A53, 2 Nov): Android 15 and
// later draw apps edge to edge (targetSdk 36), so every bottom control keeps
// clear of the bar itself. Three-button navigation (48 dp) and gesture
// navigation (24 dp), at the phone, cover screen and unfolded sizes, with
// 200% text; and the sides in landscape.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/screens/calls/call_widgets.dart';
import 'package:voiceplatform_app/screens/calls/in_call_screen.dart';
import 'package:voiceplatform_app/screens/calls/incoming_screen.dart';
import 'package:voiceplatform_app/screens/messages/thread_screen.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'test-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
);

final _now = DateTime.utc(2026, 10, 27, 4, 40);

/// A window with the status bar on top and the navigation bar's [bottom]
/// (and, in landscape, [side]) as Android reports them.
void _window(
  WidgetTester tester,
  Size size, {
  required double bottom,
  double side = 0,
  double text = 1,
}) {
  const dpr = 2.0;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  final p = FakeViewPadding(
    top: artboardStatusBar * dpr,
    bottom: bottom * dpr,
    left: side * dpr,
    right: side * dpr,
  );
  tester.view.padding = p;
  tester.view.viewPadding = p;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<FakeCallEngine> _app(WidgetTester tester) async {
  final e = FakeCallEngine(
    outgoing: OutgoingScript.manual,
    registerAfter: Duration.zero,
  );
  await e.start();
  await e.register(_account);
  await tester.pumpWidget(
    await appUnderTest(
      engine: e,
      clock: () => _now,
      api: FakeApi({
        for (final t in fx.threads)
          'POST /messages/threads/${t['id']}/read': (_) => null,
      }),
    ),
  );
  await _settle(tester);
  return e;
}

Future<void> _end(WidgetTester t, FakeCallEngine e) async {
  await t.pumpWidget(const SizedBox());
  await e.dispose();
}

/// [control] lies wholly inside the window less the system bars, once
/// scrolled into view if it sits in a scrolling part (the scrolling part
/// itself must end above the bar for that to hold).
Future<void> _shown(
  WidgetTester tester,
  Finder control,
  Size size, {
  required double bottom,
  double side = 0,
  String? what,
}) async {
  await tester.ensureVisible(control.first);
  await tester.pump();
  _clear(tester, control, size, bottom: bottom, side: side, what: what);
}

/// [control] lies wholly inside the window less the system bars.
void _clear(
  WidgetTester tester,
  Finder control,
  Size size, {
  required double bottom,
  double side = 0,
  String? what,
}) {
  expect(control, findsWidgets, reason: what);
  for (final e in control.evaluate()) {
    final r = tester.getRect(find.byElementPredicate((x) => x == e));
    final reason = '${what ?? control} at $r, bar $bottom, side $side';
    expect(
      r.bottom,
      lessThanOrEqualTo(size.height - bottom + 0.01),
      reason: reason,
    );
    expect(r.left, greaterThanOrEqualTo(side - 0.01), reason: reason);
    expect(
      r.right,
      lessThanOrEqualTo(size.width - side + 0.01),
      reason: reason,
    );
  }
}

/// Scrolls the call screen's [label] control into view and presses it.
Future<void> _press(WidgetTester tester, String label) async {
  final c = find
      .descendant(
        of: find.byWidgetPredicate(
          (w) => w is InCallScreen || w is IncomingScreen,
        ),
        matching: find.bySemanticsLabel(label),
      )
      .first;
  await tester.ensureVisible(c);
  await tester.pump();
  await tester.tap(c);
}

Future<void> _answer(WidgetTester tester, FakeCallEngine e) async {
  await tester.runAsync(
    () async => e.simulateIncoming(
      remoteNumber: '+61491570737',
      info: const IncomingInfo(
        calledNumber: '+61355501201',
        calledLabel: 'Sales group',
      ),
    ),
  );
  await _settle(tester);
}

const _sizes = [
  Size(360, 800),
  Size(412, 915),
  Size(368, 904), // a folding phone's cover screen
  Size(884, 1030), // unfolded
];

void main() {
  setUpAll(loadAppFonts);

  for (final (nav, bottom) in [('three-button', 48.0), ('gesture', 24.0)]) {
    for (final size in _sizes) {
      for (final text in [1.0, 2.0]) {
        final at =
            '${size.width.toInt()} x ${size.height.toInt()}, $nav, '
            '${(text * 100).toInt()}% text';

        testWidgets('keypad tab, $at', (tester) async {
          _window(tester, size, bottom: bottom, text: text);
          final e = await _app(tester);
          await _shown(
            tester,
            find.bySemanticsLabel('Call'),
            size,
            bottom: bottom,
            what: 'Call',
          );
          if (size.width < 600) {
            _clear(
              tester,
              find.byType(VpTabBar),
              size,
              bottom: 0,
              what: 'tab bar',
            );
            for (final label in ['Keypad', 'Me']) {
              _clear(
                tester,
                find.descendant(
                  of: find.byType(VpTabBar),
                  matching: find.text(label),
                ),
                size,
                bottom: bottom,
                what: '$label tab',
              );
            }
          } else {
            _clear(
              tester,
              find.descendant(
                of: find.byType(VpNavRail),
                matching: find.text('AN'),
              ),
              size,
              bottom: bottom,
              what: 'own status on the rail',
            );
          }
          await _end(tester, e);
        });

        testWidgets('incoming, $at', (tester) async {
          _window(tester, size, bottom: bottom, text: text);
          final e = await _app(tester);
          await _answer(tester, e);
          for (final c in ['Answer', 'Decline', 'To voicemail']) {
            _clear(
              tester,
              find.bySemanticsLabel(c),
              size,
              bottom: bottom,
              what: c,
            );
          }
          await _end(tester, e);
        });

        testWidgets('in call, with and without the keypad, $at', (
          tester,
        ) async {
          _window(tester, size, bottom: bottom, text: text);
          final e = await _app(tester);
          await _answer(tester, e);
          await _press(tester, 'Answer');
          await _settle(tester);
          _clear(
            tester,
            find.bySemanticsLabel('Hang up'),
            size,
            bottom: bottom,
            what: 'Hang up',
          );
          await _press(tester, 'Keypad');
          await _settle(tester);
          _clear(
            tester,
            find.bySemanticsLabel('Hang up'),
            size,
            bottom: bottom,
            what: 'Hang up with the keypad',
          );
          await _shown(
            tester,
            find.text('Hide keypad'),
            size,
            bottom: bottom,
            what: 'Hide keypad',
          );
          await _shown(
            tester,
            find.bySemanticsLabel('Hash'),
            size,
            bottom: bottom,
            what: 'the # key',
          );
          await _end(tester, e);
        });

        testWidgets('the reply box, $at', (tester) async {
          _window(tester, size, bottom: bottom, text: text);
          final e = await _app(tester);
          final rail = find.descendant(
            of: find.byType(VpNavRail),
            matching: find.text('Messages'),
          );
          await tester.tap(
            rail.evaluate().isNotEmpty
                ? rail
                : find.descendant(
                    of: find.byType(VpTabBar),
                    matching: find.text('Messages'),
                  ),
          );
          await _settle(tester);
          if (size.width < 680) {
            await tester.tap(find.text('Olivia Chen').first);
            await _settle(tester);
          }
          final box = find.descendant(
            of: find.byType(ThreadView),
            matching: find.byType(TextField),
          );
          _clear(tester, box, size, bottom: bottom, what: 'reply box');
          _clear(
            tester,
            find.bySemanticsLabel('Send'),
            size,
            bottom: bottom,
            what: 'Send',
          );
          await _end(tester, e);
        });
      }
    }
  }

  testWidgets('offline: the banner and the keypad clear of the bar', (
    tester,
  ) async {
    const size = Size(360, 800);
    _window(tester, size, bottom: 48, text: 2);
    final e = FakeCallEngine(outgoing: OutgoingScript.manual);
    await tester.pumpWidget(await appUnderTest(engine: e, offline: true));
    await _settle(tester);
    await _shown(
      tester,
      find.bySemanticsLabel('Call, unavailable while offline'),
      size,
      bottom: 48,
    );
    await _end(tester, e);
  });

  for (final size in [const Size(800, 360), const Size(915, 412)]) {
    testWidgets('landscape ${size.width.toInt()} x ${size.height.toInt()}: '
        'the call clear of a side bar', (tester) async {
      _window(tester, size, bottom: 0, side: 48);
      final e = await _app(tester);
      await _answer(tester, e);
      await _press(tester, 'Answer');
      await _settle(tester);
      // Hang up is pinned; the others scroll into view if they must.
      for (final c in ['Hang up', 'Mute', 'Keypad', 'Add call']) {
        await _shown(
          tester,
          find.descendant(
            of: find.byType(InCallScreen),
            matching: find.bySemanticsLabel(c),
          ),
          size,
          bottom: 0,
          side: 48,
          what: c,
        );
      }
      await _end(tester, e);
    });
  }

  for (final size in [const Size(800, 360), const Size(915, 412)]) {
    testWidgets('landscape ${size.width.toInt()} x ${size.height.toInt()}: '
        'the keypad and the reply box clear of a side bar', (tester) async {
      _window(tester, size, bottom: 0, side: 48);
      final e = await _app(tester);
      await _shown(
        tester,
        find.bySemanticsLabel('Call'),
        size,
        bottom: 0,
        side: 48,
        what: 'Call',
      );
      await _shown(
        tester,
        find.bySemanticsLabel('Hash'),
        size,
        bottom: 0,
        side: 48,
        what: 'the # key',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(VpNavRail),
          matching: find.text('Messages'),
        ),
      );
      await _settle(tester);
      await _shown(
        tester,
        find.bySemanticsLabel('Send'),
        size,
        bottom: 0,
        side: 48,
        what: 'Send',
      );
      await _end(tester, e);
    });
  }

  for (final size in [const Size(360, 800), const Size(368, 904)]) {
    testWidgets('in-call keypad open, ${size.width.toInt()} x '
        '${size.height.toInt()}: the avatar and waveform make way; the name, '
        'the timer and the Encrypted tag stay in view', (tester) async {
      _window(tester, size, bottom: 48);
      final e = await _app(tester);
      await _answer(tester, e);
      await _press(tester, 'Answer');
      await _settle(tester);
      final inCall = find.byType(InCallScreen);
      Finder within(Finder f) => find.descendant(of: inCall, matching: f);
      expect(within(find.byType(CallAvatar)), findsOneWidget);
      expect(within(find.byType(LiveWaveform)), findsOneWidget);
      await _press(tester, 'Keypad');
      await _settle(tester);
      expect(within(find.byType(CallAvatar)), findsNothing);
      expect(within(find.byType(LiveWaveform)), findsNothing);
      // In view without scrolling: above Hang up and the bar.
      final hangUp = tester.getRect(within(find.bySemanticsLabel('Hang up')));
      for (final (what, f) in [
        ('name', within(find.text('Jordan Price'))),
        ('timer', within(find.bySemanticsLabel(RegExp('^Call time')))),
        ('Encrypted', within(find.text('ENCRYPTED'))),
      ]) {
        expect(f, findsOneWidget, reason: what);
        final r = tester.getRect(f);
        expect(r.top, greaterThanOrEqualTo(artboardStatusBar), reason: what);
        expect(r.bottom, lessThanOrEqualTo(hangUp.top), reason: what);
      }
      await _end(tester, e);
    });
  }
}
