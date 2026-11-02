// FoldKeypad and FoldInCall at 884 x 1030 (2x), light and dark (dark follows
// the dark tokens; there is no dark Fold artboard), at 3:40 pm on Tuesday
// 27 October in Melbourne. The keypad as on the artboard: 0491 typed, then
// Jordan Price picked from the matches, which fills "0491 570 737" and
// "Jordan Price, Harbour Cafe". Also nothing typed (the colleagues free
// now, TJ's decision), the proof widths (690 Galaxy Z Fold5 portrait, 680
// the narrowest split at 200% text, 679 centred, 744, 852), and the call
// with its caller beside it.
//
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_matches.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);

const _account = SipAccount(
  authUsername: 'mock-202-pixel8',
  password: 'test-password',
  domain: 'sip.demo-co.example',
  outboundProxy: 'sip:sip.voiceplatform.example:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  instanceId: 'urn:uuid:60000000-0000-4000-8000-000000000001',
);

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
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

Future<FakeCallEngine> _start(
  WidgetTester tester, {
  required ThemePreference theme,
  required Size size,
  double text = 1,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.reset);
  // Connected 3:12 ago, as on FoldInCall; a steady level for the waveform.
  final e = FakeCallEngine(
    outgoing: OutgoingScript.manual,
    registerAfter: Duration.zero,
    clock: () => _now.subtract(const Duration(seconds: 192)),
  )..levelPattern = (_) => 1;
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

Future<void> _shot(WidgetTester t, FakeCallEngine e, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(name));
  await t.pumpWidget(const SizedBox());
  await e.dispose();
}

Future<void> _pickJordan(WidgetTester tester) async {
  await _type(tester, '0491');
  await _settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(KeypadMatchesPane),
      matching: find.text('Jordan Price'),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  for (final (name, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('FoldKeypad, $name', (tester) async {
      final e = await _start(tester, theme: pref, size: const Size(884, 1030));
      await _pickJordan(tester);
      await _shot(tester, e, 'keypad_wide_$name.png');
    });

    testWidgets('FoldKeypad, nothing typed, $name', (tester) async {
      final e = await _start(tester, theme: pref, size: const Size(884, 1030));
      await _shot(tester, e, 'keypad_wide_free_$name.png');
    });

    testWidgets('keypad, 690 dp (Galaxy Z Fold5 portrait), $name', (
      tester,
    ) async {
      final e = await _start(tester, theme: pref, size: const Size(690, 1030));
      await _pickJordan(tester);
      await _shot(tester, e, 'keypad_wide_690_$name.png');
    });

    testWidgets('keypad, 680 dp at 200% text, $name', (tester) async {
      final e = await _start(
        tester,
        theme: pref,
        size: const Size(680, 1030),
        text: 2,
      );
      await _pickJordan(tester);
      await _shot(tester, e, 'keypad_wide_680_200pct_$name.png');
    });

    testWidgets('keypad, 679 dp: centred at phone width, $name', (
      tester,
    ) async {
      final e = await _start(tester, theme: pref, size: const Size(679, 1030));
      await _type(tester, '0491570737');
      await _settle(tester);
      await _shot(tester, e, 'keypad_wide_679_$name.png');
    });

    testWidgets('FoldInCall, $name', (tester) async {
      final e = await _start(tester, theme: pref, size: const Size(884, 1030));
      await tester.runAsync(
        () async => e.simulateIncoming(
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
      await tester.runAsync(() => e.setAudioRoute(AudioRoute.speaker));
      await _settle(tester);
      await _shot(tester, e, 'in_call_wide_$name.png');
    });
  }

  for (final w in [744.0, 852.0]) {
    testWidgets('keypad, ${w.toInt()} dp, light', (tester) async {
      final e = await _start(
        tester,
        theme: ThemePreference.light,
        size: Size(w, 1030),
      );
      await _pickJordan(tester);
      await _shot(tester, e, 'keypad_wide_${w.toInt()}_light.png');
    });
  }

  testWidgets('in call, 690 dp at 200% text', (tester) async {
    final e = await _start(
      tester,
      theme: ThemePreference.light,
      size: const Size(690, 1030),
      text: 2,
    );
    await tester.runAsync(
      () async => e.simulateIncoming(remoteNumber: '+61491570737'),
    );
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Answer'));
    await _settle(tester);
    await _shot(tester, e, 'in_call_wide_690_200pct.png');
  });
}
