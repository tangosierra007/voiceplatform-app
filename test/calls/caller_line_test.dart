// The caller line on the call screens (TJ's A53 run, 2 Nov): service codes
// keep their star and hash; a caller is their best name or the national
// number once, never "+61..." with a "+" avatar; the line called heads an
// inbound call as it does an outbound one, and never reads blank.
import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/calls/numbers.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/screens/calls/call_widgets.dart';
import 'package:voiceplatform_app/screens/calls/in_call_screen.dart';
import 'package:voiceplatform_app/screens/calls/incoming_screen.dart';

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

Future<FakeCallEngine> _app(WidgetTester tester) async {
  usePhone(tester);
  final e = FakeCallEngine(
    outgoing: OutgoingScript.manual,
    registerAfter: Duration.zero,
  );
  await e.start();
  await e.register(_account);
  await tester.pumpWidget(await appUnderTest(engine: e, api: FakeApi({})));
  await _settle(tester);
  return e;
}

Future<void> _end(WidgetTester t, FakeCallEngine e) async {
  await t.pumpWidget(const SizedBox());
  await e.dispose();
}

CallSnapshot _call({String number = '+61491579760', String? name}) =>
    CallSnapshot(
      id: 'c1',
      direction: CallDirection.incoming,
      state: CallState.connected,
      remoteNumber: number,
      remoteName: name,
      startedAt: DateTime.utc(2026, 11, 2),
    );

/// Every text on screen, for "shown once" checks.
List<String> _texts(WidgetTester t) => [
  for (final w in t.widgetList<Text>(find.byType(Text)))
    if (w.data != null) w.data!,
];

void main() {
  setUpAll(loadAppFonts);

  group('(a) service codes', () {
    test('keep their star and hash', () {
      expect(formatAuNumber('*97'), '*97');
      expect(formatAuNumber('#31#0491570737'), '#31#0491570737');
      expect(formatAuNumber('*10#'), '*10#');
      // Numbers are as before.
      expect(formatAuNumber('+61491570737'), '0491 570 737');
      expect(formatAuNumber('302'), '302');
    });

    test('are nobody\'s number', () {
      final m = ContactMatcher(
        colleagues: [
          Colleague.fromJson({
            'userId': 'u1',
            'name': 'Somebody',
            'initials': 'S',
            'extension': '97',
            'presence': {'extension': '97', 'presence': 'available'},
          }),
        ],
      );
      expect(m.match('97')?.name, 'Somebody');
      expect(m.match('*97'), isNull);
    });

    testWidgets('dialling *97: the keypad and the call show "*97"', (
      tester,
    ) async {
      final e = await _app(tester);
      await tester.tap(find.bySemanticsLabel('Star'));
      await tester.pump();
      for (final d in ['9 WXYZ', '7 PQRS']) {
        await tester.tap(find.bySemanticsLabel(d));
        await tester.pump();
      }
      expect(find.text('*97'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Call'));
      await _settle(tester);
      expect(find.byType(InCallScreen), findsOneWidget);
      expect(find.text('*97'), findsOneWidget);
      expect(find.text('97'), findsNothing);
      await _end(tester, e);
    });
  });

  group('(b) the caller', () {
    test('a name that is only a number is no name', () {
      expect(networkName('+61491579760'), isNull);
      expect(networkName('0491 579 760'), isNull);
      expect(networkName('  '), isNull);
      expect(networkName('anonymous'), isNull);
      expect(networkName('Jordan Price'), 'Jordan Price');
    });

    test('a name that only says the number is hidden is no name', () {
      for (final n in [
        'Private',
        'PRIVATE',
        'private',
        'Withheld',
        'WITHHELD',
        ' withheld ',
        'Restricted',
        'RESTRICTED',
        'restricted',
      ]) {
        expect(networkName(n), isNull, reason: n);
      }
      // A real name that only contains one of the words stays.
      expect(networkName('Private Hospital'), 'Private Hospital');
    });

    test('best name: a match on this phone, then the network, then none', () {
      final matcher = ContactMatcher(
        shared: [
          SharedContact.fromJson({
            'id': 's1',
            'name': 'Jordan Price',
            'company': 'Harbour Cafe',
            'numbers': [
              {'label': 'Mobile', 'number': '+61491579760'},
            ],
          }),
        ],
        phone: const [
          PhoneContact('Dana Ho', ['0491 576 398']),
        ],
      );
      expect(
        callerName(_call(name: 'JORDAN P MOBILE'), matcher),
        'Jordan Price',
      );
      expect(
        callerName(
          _call(number: '+61491576398', name: '+61491576398'),
          matcher,
        ),
        'Dana Ho',
      );
      expect(
        callerName(_call(number: '+61491576801', name: 'Westgate'), matcher),
        'Westgate',
      );
      final bare = _call(number: '+61491576801', name: '+61491576801');
      expect(callerName(bare, matcher), isNull);
      expect(callTitle(bare, null), '0491 576 801');
      expect(callSubtitle(bare, null), isNull);
    });

    for (final screen in ['incoming', 'in call']) {
      testWidgets(
        '$screen: a bare inbound number once, no "+", no "+" avatar',
        (tester) async {
          final e = await _app(tester);
          await tester.runAsync(
            () async => e.simulateIncoming(
              remoteNumber: '+61491579760',
              remoteName: '+61491579760',
              info: const IncomingInfo(),
            ),
          );
          await _settle(tester);
          if (screen == 'in call') {
            await tester.tap(find.bySemanticsLabel('Answer'));
            await _settle(tester);
            expect(find.byType(InCallScreen), findsOneWidget);
          } else {
            expect(find.byType(IncomingScreen), findsOneWidget);
          }
          final texts = _texts(tester);
          expect(texts.where((t) => t == '0491 579 760'), hasLength(1));
          expect(texts.where((t) => t.contains('+')), isEmpty);
          final avatar = tester.widget<CallAvatar>(find.byType(CallAvatar));
          expect(avatar.name, isNull, reason: 'the neutral handset');
          await _end(tester, e);
        },
      );
    }

    testWidgets('a phonebook caller: their name, then the number', (
      tester,
    ) async {
      final e = await _app(tester);
      await tester.runAsync(
        () async => e.simulateIncoming(
          remoteNumber: '+61491570737',
          remoteName: '+61491570737',
        ),
      );
      await _settle(tester);
      expect(find.text('Jordan Price'), findsOneWidget);
      expect(find.text('0491 570 737'), findsOneWidget);
      expect(
        tester.widget<CallAvatar>(find.byType(CallAvatar)).name,
        'Jordan Price',
      );
      await _end(tester, e);
    });
  });

  group('(c) the line called, inbound', () {
    testWidgets('from X-VP-Called: on the incoming screen and in the call', (
      tester,
    ) async {
      final e = await _app(tester);
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
      expect(find.text('INCOMING · SALES GROUP'), findsOneWidget);
      expect(find.textContaining('Called 03 5550 1201 Sales.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      expect(find.text('SALES · 03 5550 1201'), findsOneWidget);
      await _end(tester, e);
    });

    testWidgets('without it (the platform not sending it yet): never blank', (
      tester,
    ) async {
      final e = await _app(tester);
      await tester.runAsync(
        () async => e.simulateIncoming(
          remoteNumber: '+61491579760',
          info: const IncomingInfo(),
        ),
      );
      await _settle(tester);
      expect(find.text('INCOMING CALL'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      expect(find.text('INCOMING CALL'), findsOneWidget);
      await _end(tester, e);
    });
  });
}
