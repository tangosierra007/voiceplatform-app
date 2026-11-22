// The Keypad on a short window (FU56, Q309-4, task 401), 2x, at 3:40 pm on
// Tuesday 27 October in Melbourne: the A3 folded landscape (797 x 443, light
// and dark, 100 % and 200 % text), 400 dp tall at 200 %, the artboard phone
// at 200 % (now short, so Call is in view), offline, and More open.
//
//   flutter test --update-goldens test/goldens/short_keypad_golden_test.dart
@Tags(['golden'])
library;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
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
  bool offline = false,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.reset);
  final e = FakeCallEngine(
    outgoing: OutgoingScript.manual,
    registerAfter: Duration.zero,
    clock: () => _now,
  );
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

Future<void> _shot(WidgetTester t, FakeCallEngine e, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(name));
  await t.pumpWidget(const SizedBox());
  await e.dispose();
}

void main() {
  setUpAll(loadAppFonts);

  for (final (name, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('short keypad, 797 x 443, $name', (tester) async {
      final e = await _start(tester, theme: pref, size: const Size(797, 443));
      await _type(tester, '0491570737');
      await _settle(tester);
      await _shot(tester, e, 'keypad_short_797x443_$name.png');
    });
  }

  testWidgets('short keypad, 797 x 443 at 200%', (tester) async {
    final e = await _start(
      tester,
      theme: ThemePreference.light,
      size: const Size(797, 443),
      text: 2,
    );
    await _type(tester, '0491570737');
    await _settle(tester);
    await _shot(tester, e, 'keypad_short_797x443_200pct_light.png');
  });

  testWidgets('short keypad, 797 x 400 at 200%', (tester) async {
    final e = await _start(
      tester,
      theme: ThemePreference.light,
      size: const Size(797, 400),
      text: 2,
    );
    await _type(tester, '0491570737');
    await _settle(tester);
    await _shot(tester, e, 'keypad_short_797x400_200pct_light.png');
  });

  testWidgets('the artboard phone at 200%: short', (tester) async {
    final e = await _start(
      tester,
      theme: ThemePreference.light,
      size: phoneSize,
      text: 2,
    );
    await _type(tester, '0491570737');
    await _settle(tester);
    await _shot(tester, e, 'keypad_short_390x844_200pct_light.png');
  });

  testWidgets('short keypad, offline, 797 x 443', (tester) async {
    final e = await _start(
      tester,
      theme: ThemePreference.light,
      size: const Size(797, 443),
      offline: true,
    );
    await _shot(tester, e, 'keypad_short_797x443_offline_light.png');
  });

  testWidgets('short keypad, More open, 797 x 443', (tester) async {
    final e = await _start(
      tester,
      theme: ThemePreference.light,
      size: const Size(797, 443),
    );
    await tester.tap(find.bySemanticsLabel('More'));
    await _settle(tester);
    await _shot(tester, e, 'keypad_short_797x443_more_light.png');
  });
}
