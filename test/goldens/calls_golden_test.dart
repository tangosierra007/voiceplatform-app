// Goldens for the call screens at 390 x 844 (2x), light and dark, set up as
// the artboards show them (AppKeypad, AppOffline, AppIncoming, AppInCall,
// AppTransfer, AppMicrophone). Side by side with the artboards in
// test/goldens/compare/calls_side_by_side.png.
@Tags(['golden'])
library;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

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

Future<FakeCallEngine> _engine() async {
  // Connected 84 s ago, so the timer reads 01:24 as on the artboard; a
  // steady full input level, so the waveform has the artboard's heights.
  final e = FakeCallEngine(
    outgoing: OutgoingScript.manual,
    registerAfter: Duration.zero,
    clock: () => _now.subtract(const Duration(seconds: 84)),
  )..levelPattern = (_) => 1;
  await e.start();
  await e.register(_account);
  return e;
}

/// One fixed moment for the engine and the screens' timers.
final _now = DateTime.now();

Future<void> _shot(WidgetTester t, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile(name));

void main() {
  setUpAll(loadAppFonts);

  for (final (mode, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('AppKeypad $mode', (tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(
        await appUnderTest(engine: e, theme: pref, clock: () => _now),
      );
      await _settle(tester);
      await _type(tester, '0491570737');
      await _settle(tester);
      await _shot(tester, 'keypad_$mode.png');
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });

    testWidgets('AppOffline $mode', (tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(
        await appUnderTest(engine: e, theme: pref, offline: true),
      );
      await _settle(tester);
      await _shot(tester, 'offline_$mode.png');
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });

    testWidgets('AppIncoming $mode', (tester) async {
      usePhone(tester);
      final e = await _engine();
      final now = DateTime.now();
      await tester.pumpWidget(
        await appUnderTest(engine: e, theme: pref, clock: () => now),
      );
      await _settle(tester);
      await tester.runAsync(
        () async => e.simulateIncoming(
          remoteNumber: '+61355501987',
          remoteName: 'Westgate Supplies',
          info: IncomingInfo(
            calledNumber: '+61355501201',
            calledLabel: 'Sales group',
            alsoRinging: const ["Mia's desk phone"],
            repeatCount: 3,
            lastAnsweredBy: 'Tom Walsh',
            lastAnsweredAt: DateTime(now.year, now.month, now.day, 14, 2),
          ),
        ),
      );
      await _settle(tester);
      await _shot(tester, 'incoming_$mode.png');
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });

    Future<String> inCall(WidgetTester tester, FakeCallEngine e) async {
      late String id;
      await tester.runAsync(
        () async => id = e.simulateIncoming(
          remoteNumber: '+61491570737',
          info: const IncomingInfo(
            calledNumber: '+61355501201',
            calledLabel: 'Sales',
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      return id;
    }

    testWidgets('AppInCall $mode', (tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(
        await appUnderTest(engine: e, theme: pref, clock: () => _now),
      );
      await _settle(tester);
      await inCall(tester, e);
      await tester.runAsync(() => e.setAudioRoute(AudioRoute.speaker));
      await _settle(tester);
      await _shot(tester, 'in_call_$mode.png');
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });

    testWidgets('AppTransfer $mode', (tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(
        await appUnderTest(engine: e, theme: pref, clock: () => _now),
      );
      await _settle(tester);
      await inCall(tester, e);
      await tester.tap(find.bySemanticsLabel('Transfer'));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Mia Rossi')));
      await _settle(tester);
      await _shot(tester, 'transfer_$mode.png');
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });

    testWidgets('AppMicrophone $mode', (tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(
        await appUnderTest(
          engine: e,
          theme: pref,
          mic: FakeMic(granted: false, grantOnRequest: false),
        ),
      );
      await _settle(tester);
      await _type(tester, '0491570737');
      await tester.tap(find.bySemanticsLabel('Call'));
      await _settle(tester);
      await _shot(tester, 'microphone_$mode.png');
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });
  }
}
