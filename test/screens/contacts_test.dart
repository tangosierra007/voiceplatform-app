// AppContacts on the canvas sample data, with live presence.
import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

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

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

Finder _button(String label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      w.properties.label == label,
);

final _now = DateTime.utc(2026, 10, 27, 0, 10);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Colleagues: real counts, presence text, the call buttons', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(clock: () => _now));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    // 22 in the tenant; free counted from presence (Mia, Priya, Tom).
    expect(find.text('22 COLLEAGUES · 3 FREE NOW'), findsOneWidget);
    for (final t in [
      'Ava Nguyen',
      '202 · On a call · 1:37',
      'Reception',
      '201 · On a call · 4:12',
      "Liam O'Brien",
      '205 · Do not disturb',
      'Mia Rossi',
      '206 · Available',
      '302 · Available',
      '312 · Offline',
      '301 · Available on mobile',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(_button('Call Mia Rossi'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is TextField), findsOneWidget);
  });

  testWidgets('presence events update the dots, text and free count live', (
    tester,
  ) async {
    usePhone(tester);
    final events = StreamController<ServerEvent>.broadcast();
    final live = LiveEvents(
      connect: () => events.stream,
      poll: (_) async => (items: null, etag: null),
    );
    await tester.pumpWidget(await appUnderTest(clock: () => _now, live: live));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    await tester.runAsync(() async {
      events.add(
        const ServerEvent('presence', {'extension': '206', 'presence': 'dnd'}),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await _settle(tester);
    expect(find.text('206 · Do not disturb'), findsOneWidget);
    expect(find.text('22 COLLEAGUES · 2 FREE NOW'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await live.dispose();
    await events.close();
  });

  testWidgets('search filters by name and extension', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(clock: () => _now));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '30');
    await _settle(tester);
    expect(find.text('Priya Shah'), findsOneWidget);
    expect(find.text('Tom Walsh'), findsOneWidget);
    expect(find.text('Mia Rossi'), findsNothing);
  });

  testWidgets('the call button dials the extension', (tester) async {
    usePhone(tester);
    final e = FakeCallEngine(
      outgoing: OutgoingScript.manual,
      registerAfter: Duration.zero,
    );
    await e.start();
    await e.register(_account);
    await tester.pumpWidget(await appUnderTest(engine: e, clock: () => _now));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    await tester.tap(_button('Call Mia Rossi'));
    await _settle(tester);
    expect(e.activeCalls.single.remoteNumber, '206');
    await tester.pumpWidget(const SizedBox());
    await e.dispose();
  });

  testWidgets('Teams: members and free now; tap shows the members', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(clock: () => _now));
    await _settle(tester);
    await tester.tap(_tab('Contacts'));
    await _settle(tester);
    await tester.tap(find.text('Teams'));
    await _settle(tester);
    expect(find.text('3 TEAMS'), findsOneWidget);
    expect(find.text('3 people · 1 free now · 03 5550 1201'), findsOneWidget);
    expect(_button('Call Sales'), findsOneWidget);
    expect(find.text('Mia Rossi'), findsNothing);
    await tester.tap(find.text('Sales'));
    await _settle(tester);
    expect(find.text('Mia Rossi'), findsOneWidget);
    expect(find.text("Liam O'Brien"), findsOneWidget);
  });
}
