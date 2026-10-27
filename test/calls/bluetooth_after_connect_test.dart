// BLUETOOTH_CONNECT is asked once a call connects, never before answering
// or dialling (WS6), including answering after a trip to Settings for the
// microphone.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';

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
  await t.pump(const Duration(milliseconds: 400));
}

Future<FakeCallEngine> _engine() async {
  final e = FakeCallEngine(
    outgoing: OutgoingScript.manual,
    registerAfter: Duration.zero,
  );
  await e.start();
  await e.register(_account);
  return e;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('incoming: nothing asked while ringing; asked once connected', (
    tester,
  ) async {
    usePhone(tester);
    final e = await _engine();
    final mic = FakeMic();
    await tester.pumpWidget(await appUnderTest(engine: e, mic: mic));
    await _settle(tester);
    await tester.runAsync(
      () async => e.simulateIncoming(remoteNumber: '+61355501987'),
    );
    await _settle(tester);
    expect(mic.bluetoothAsks, 0);
    await tester.tap(find.bySemanticsLabel('Answer'));
    await _settle(tester);
    expect(e.activeCalls.single.state, CallState.connected);
    expect(mic.bluetoothAsks, 1);
    // Hold and resume is not a new connection.
    await tester.runAsync(() async {
      await e.hold(e.activeCalls.single.id);
      await e.resume(e.activeCalls.single.id);
    });
    await _settle(tester);
    expect(mic.bluetoothAsks, 1);
    await tester.pumpWidget(const SizedBox());
    await e.dispose();
  });

  testWidgets('outgoing: not before dialling; asked when it connects', (
    tester,
  ) async {
    usePhone(tester);
    final e = await _engine();
    final mic = FakeMic();
    await tester.pumpWidget(await appUnderTest(engine: e, mic: mic));
    await _settle(tester);
    for (final d in ['2', '0', '6']) {
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
    expect(e.activeCalls.single.state, CallState.dialling);
    expect(mic.bluetoothAsks, 0);
    await tester.runAsync(() async => e.remoteAnswer(e.activeCalls.single.id));
    await _settle(tester);
    expect(mic.bluetoothAsks, 1);
    await tester.pumpWidget(const SizedBox());
    await e.dispose();
  });

  testWidgets('answering after Settings: asked once connected', (tester) async {
    usePhone(tester);
    final e = await _engine();
    // Refused at first; granted on coming back from Settings.
    final mic = FakeMic(granted: false, grantOnRequest: false);
    await tester.pumpWidget(await appUnderTest(engine: e, mic: mic));
    await _settle(tester);
    await tester.runAsync(
      () async => e.simulateIncoming(remoteNumber: '+61355501987'),
    );
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Answer'));
    await _settle(tester);
    expect(mic.bluetoothAsks, 0);
    expect(find.text('Open Settings'), findsOneWidget);
    // Back from Settings with the microphone allowed.
    mic.granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    await _settle(tester);
    expect(e.activeCalls.single.state, CallState.connected);
    expect(mic.bluetoothAsks, 1);
    await tester.pumpWidget(const SizedBox());
    await e.dispose();
  });
}
