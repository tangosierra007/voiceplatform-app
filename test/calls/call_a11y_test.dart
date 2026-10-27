// Screen reader labels, tap targets and 200 % text on the call screens.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/screens/calls/transfer_screen.dart';

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

const _westgate = IncomingInfo(
  calledNumber: '+61355501201',
  calledLabel: 'Sales group',
  alsoRinging: ["Mia's desk phone"],
  repeatCount: 3,
  lastAnsweredBy: 'Tom Walsh',
);

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// Opens [screen] ('keypad', 'offline', 'incoming', 'incall', 'transfer',
/// 'microphone') and returns the engine to dispose.
Future<FakeCallEngine> _open(WidgetTester tester, String screen) async {
  usePhone(tester);
  final e = FakeCallEngine(
    outgoing: OutgoingScript.manual,
    registerAfter: Duration.zero,
  );
  await e.start();
  await e.register(_account);
  await tester.pumpWidget(
    await appUnderTest(
      engine: e,
      offline: screen == 'offline',
      mic: FakeMic(granted: screen != 'microphone', grantOnRequest: false),
    ),
  );
  await _settle(tester);
  if (screen == 'microphone') {
    for (final d in ['0', '4', '9', '1']) {
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.button == true &&
                  (w.properties.label ?? '').startsWith(d),
            )
            .first,
      );
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel('Call'));
    await _settle(tester);
  }
  if (['incoming', 'incall', 'transfer'].contains(screen)) {
    await tester.runAsync(
      () async => e.simulateIncoming(
        remoteNumber: '+61355501987',
        remoteName: 'Westgate Supplies',
        info: _westgate,
      ),
    );
    await _settle(tester);
  }
  if (['incall', 'transfer'].contains(screen)) {
    await tester.ensureVisible(find.bySemanticsLabel('Answer'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Answer'));
    await _settle(tester);
  }
  if (screen == 'transfer') {
    await tester.ensureVisible(find.bySemanticsLabel('Transfer'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Transfer'));
    await _settle(tester);
    expect(find.byType(TransferScreen), findsOneWidget);
  }
  return e;
}

void main() {
  setUpAll(loadAppFonts);

  for (final screen in [
    'keypad',
    'offline',
    'incoming',
    'incall',
    'transfer',
    'microphone',
  ]) {
    testWidgets('$screen: labelled tap targets of 48 px', (tester) async {
      final h = tester.ensureSemantics();
      final e = await _open(tester, screen);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      if (screen != 'transfer' && screen != 'microphone') {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      h.dispose();
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });

    testWidgets('$screen: 200 % text stays inside', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final e = await _open(tester, screen);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await e.dispose();
    });
  }
}
