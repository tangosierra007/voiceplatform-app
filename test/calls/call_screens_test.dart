// Keypad, Incoming, In call, Transfer, Microphone and Offline against a
// scripted FakeCallEngine: every state the screens go through.
import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/nav/routes.dart';
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/screens/calls/in_call_screen.dart';
import 'package:voiceplatform_app/screens/calls/incoming_screen.dart';
import 'package:voiceplatform_app/screens/calls/transfer_screen.dart';
import 'package:voiceplatform_app/screens/keypad/keypad_screen.dart';
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

/// Records what the screens ask of the engine.
class SpyEngine extends FakeCallEngine {
  SpyEngine()
    : super(outgoing: OutgoingScript.manual, registerAfter: Duration.zero);
  final called = <(String, String?)>[];

  @override
  Future<String> call(String number, {String? callerId}) {
    called.add((number, callerId));
    return super.call(number, callerId: callerId);
  }
}

final _engines = <SpyEngine>[];

Future<SpyEngine> _engine() async {
  final e = SpyEngine();
  _engines.add(e);
  await e.start();
  await e.register(_account);
  return e;
}

/// Leaves the screens and stops every engine timer (the input level runs at
/// 20 Hz while a call is connected).
Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  for (final e in _engines) {
    await e.dispose();
  }
  _engines.clear();
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

GoRouter _router(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Navigator).first))
        .read(routerProvider);

const _westgate = IncomingInfo(
  calledNumber: '+61355501201',
  calledLabel: 'Sales group',
  alsoRinging: ["Mia's desk phone"],
  repeatCount: 3,
  lastAnsweredBy: 'Tom Walsh',
);

void main() {
  setUpAll(loadAppFonts);

  group('Keypad', () {
    testWidgets(
      'typing shows the number and its contact; delete; hold 0 for +',
      (tester) async {
        usePhone(tester);
        await tester.pumpWidget(await appUnderTest(engine: await _engine()));
        await _settle(tester);
        expect(find.byType(KeypadScreen), findsOneWidget);
        expect(find.text('Available'), findsOneWidget);
        expect(find.text('Calls show 03 5550 1200'), findsOneWidget);
        await _type(tester, '0491570737');
        expect(find.text('0491 570 737'), findsOneWidget);
        expect(find.text('Jordan Price, Harbour Cafe'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Delete'));
        await tester.pump();
        expect(find.text('0491 570 73'), findsOneWidget);
        await tester.longPress(find.bySemanticsLabel('Delete'));
        await tester.pump();
        expect(find.text('0491 570 73'), findsNothing);
        await tester.longPress(find.bySemanticsLabel(RegExp('^0, hold')));
        await tester.pump();
        expect(find.text('+'), findsWidgets);
      },
    );

    testWidgets(
      'call: microphone asked now, then the engine with the picked caller ID',
      (tester) async {
        usePhone(tester);
        final e = await _engine();
        final mic = FakeMic(granted: false);
        await tester.pumpWidget(await appUnderTest(engine: e, mic: mic));
        await _settle(tester);
        expect(mic.requests, 0, reason: 'never asked before a call');

        await tester.tap(find.bySemanticsLabel(RegExp('^Calls show')));
        await _settle(tester);
        await tester.tap(find.text('Sales mobile 0491 571 266'));
        await _settle(tester);
        expect(find.text('Calls show 0491 571 266'), findsOneWidget);

        await _type(tester, '0491570737');
        await tester.tap(find.bySemanticsLabel('Call'));
        await _settle(tester);
        expect(mic.requests, 1);
        expect(e.called.single, ('0491570737', '+61491571266'));
        expect(find.byType(InCallScreen), findsOneWidget);
        expect(find.text('Jordan Price'), findsOneWidget);
        expect(find.text('SALES MOBILE · 0491 571 266'), findsOneWidget);
        expect(find.text('Calling'), findsOneWidget);
        await _end(tester);
      },
    );

    testWidgets('the default caller ID goes as null (the extension default)', (
      tester,
    ) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(await appUnderTest(engine: e));
      await _settle(tester);
      await _type(tester, '206');
      expect(find.text('Mia Rossi, ext 206'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Call'));
      await _settle(tester);
      expect(e.called.single, ('206', null));
      await _end(tester);
    });

    for (final n in ['000', '112', '106', '0000']) {
      testWidgets(
        '$n goes to AppEmergency before the microphone or the engine',
        (tester) async {
          usePhone(tester);
          final e = await _engine();
          final mic = FakeMic(granted: false);
          await tester.pumpWidget(await appUnderTest(engine: e, mic: mic));
          await _settle(tester);
          await _type(tester, n);
          await tester.tap(find.bySemanticsLabel('Call'));
          await _settle(tester);
          expect(
            find.text("Emergency calls use your phone's own network"),
            findsOneWidget,
          );
          expect(e.called, isEmpty);
          expect(mic.requests, 0);
        },
      );
    }

    testWidgets('status chip opens the status sheet', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(await appUnderTest(engine: await _engine()));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Status: Available'));
      await _settle(tester);
      expect(
        find.text('Your desk phone shows the same status.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Do not disturb'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Status: Do not disturb'), findsOneWidget);
    });

    testWidgets('a phone contact matches only from the device list', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(
          engine: await _engine(),
          phoneContacts: const [
            PhoneContact('Sam at home', ['0491 579 455']),
          ],
        ),
      );
      await _settle(tester);
      await _type(tester, '0491579455');
      expect(find.text('Sam at home'), findsOneWidget);
    });
  });

  group('Offline', () {
    testWidgets('banner, Offline chip, call off, the 000 note', (tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(await appUnderTest(engine: e, offline: true));
      await _settle(tester);
      expect(
        find.textContaining('No internet on this phone', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.text(
          "For 000, use your phone's own dialler.\nIt works without the app.",
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Call, unavailable while offline'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel(RegExp('^5 JKL')));
      await tester.pump();
      expect(e.called, isEmpty);
    });
  });

  group('Microphone', () {
    testWidgets('refused: AppMicrophone; Open Settings; desk phone instead', (
      tester,
    ) async {
      usePhone(tester);
      final e = await _engine();
      final mic = FakeMic(granted: false, grantOnRequest: false);
      final desk = <(String, String?)>[];
      await tester.pumpWidget(
        await appUnderTest(
          engine: e,
          mic: mic,
          deskPhone: (n, id) async {
            desk.add((n, id?.value));
            return 'Desk phone 202';
          },
        ),
      );
      await _settle(tester);
      await _type(tester, '0491570737');
      await tester.tap(find.bySemanticsLabel('Call'));
      await _settle(tester);
      expect(find.text('Let the app use the microphone'), findsOneWidget);
      expect(e.called, isEmpty);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(mic.settingsOpened, 1);
      await tester.tap(find.text('Call from my desk phone instead'));
      await _settle(tester);
      expect(desk.single.$1, '0491570737');
      expect(
        find.text(
          'Desk phone 202 is ringing. Pick it up to call 0491 570 737.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('back from Settings with it on: the call starts', (
      tester,
    ) async {
      usePhone(tester);
      final e = await _engine();
      final mic = FakeMic(granted: false, grantOnRequest: false);
      await tester.pumpWidget(await appUnderTest(engine: e, mic: mic));
      await _settle(tester);
      await _type(tester, '0491570737');
      await tester.tap(find.bySemanticsLabel('Call'));
      await _settle(tester);
      mic.granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      await _settle(tester);
      expect(e.called.single.$1, '0491570737');
      await _end(tester);
    });
  });

  group('Incoming', () {
    testWidgets(
      'as the artboard: group, also ringing, repeat pill, last answered',
      (tester) async {
        usePhone(tester);
        final e = await _engine();
        await tester.pumpWidget(
          await appUnderTest(engine: e, clock: () => DateTime.now()),
        );
        await _settle(tester);
        await tester.runAsync(() async {
          e.simulateIncoming(
            remoteNumber: '+61355501987',
            remoteName: 'Westgate Supplies',
            info: IncomingInfo(
              calledNumber: _westgate.calledNumber,
              calledLabel: _westgate.calledLabel,
              alsoRinging: _westgate.alsoRinging,
              repeatCount: 3,
              lastAnsweredBy: 'Tom Walsh',
              lastAnsweredAt: DateTime.now(),
            ),
          );
        });
        await _settle(tester);
        expect(find.byType(IncomingScreen), findsOneWidget);
        expect(find.text('INCOMING · SALES GROUP'), findsOneWidget);
        expect(find.text('WS'), findsOneWidget);
        expect(find.text('Westgate Supplies'), findsOneWidget);
        expect(find.text('03 5550 1987'), findsOneWidget);
        expect(
          find.text(
            "Called 03 5550 1201 Sales. Also ringing Mia's desk phone.",
          ),
          findsOneWidget,
        );
        expect(find.text('3rd call this week'), findsOneWidget);
        expect(
          find.textContaining('Last answered by Tom Walsh, '),
          findsOneWidget,
        );
        for (final l in ['Decline', 'To voicemail', 'Answer']) {
          expect(find.bySemanticsLabel(l), findsOneWidget);
        }
      },
    );

    for (final (label, reason) in [
      ('Decline', EndReason.declined),
      ('To voicemail', EndReason.toVoicemail),
    ]) {
      testWidgets('$label ends it and goes back', (tester) async {
        usePhone(tester);
        final e = await _engine();
        final ended = <EndReason>[];
        e.calls
            .where((c) => c.state == CallState.ended)
            .listen((c) => ended.add(c.endReason!));
        await tester.pumpWidget(await appUnderTest(engine: e));
        await _settle(tester);
        await tester.runAsync(
          () async =>
              e.simulateIncoming(remoteNumber: '+61491570737', info: _westgate),
        );
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel(label));
        await _settle(tester);
        expect(ended, [reason]);
        expect(find.byType(IncomingScreen), findsNothing);
        expect(find.byType(VpTabBar), findsOneWidget);
      });
    }

    testWidgets(
      'no name from the platform: a phone contact on this device names it',
      (tester) async {
        usePhone(tester);
        final e = await _engine();
        await tester.pumpWidget(
          await appUnderTest(
            engine: e,
            phoneContacts: const [
              PhoneContact('Sam at home', ['0491 579 455']),
            ],
          ),
        );
        await _settle(tester);
        await tester.runAsync(
          () async => e.simulateIncoming(remoteNumber: '+61491579455'),
        );
        await _settle(tester);
        expect(find.text('Sam at home'), findsOneWidget);
        expect(find.text('0491 579 455'), findsOneWidget);
        expect(find.text('INCOMING CALL'), findsOneWidget);
        expect(find.textContaining('call this week'), findsNothing);
      },
    );

    testWidgets('answered elsewhere clears the screen', (tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(await appUnderTest(engine: e));
      await _settle(tester);
      late String id;
      await tester.runAsync(
        () async => id = e.simulateIncoming(remoteNumber: '+61491570737'),
      );
      await _settle(tester);
      await tester.runAsync(() async => e.simulateAnsweredElsewhere(id));
      await _settle(tester);
      expect(find.byType(IncomingScreen), findsNothing);
    });
  });

  group('In call', () {
    Future<(SpyEngine, String)> answered(
      WidgetTester tester, {
      Set<AudioRoute>? routes,
    }) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(await appUnderTest(engine: e));
      await _settle(tester);
      late String id;
      await tester.runAsync(() async {
        id = e.simulateIncoming(remoteNumber: '+61491570737', info: _westgate);
      });
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      if (routes != null) {
        // A Bluetooth headset connects during the call.
        await tester.runAsync(() async => e.simulateAudioDevices(routes));
        await _settle(tester);
      }
      return (e, id);
    }

    testWidgets('line called, timer, tags, waveform; ink in both themes', (
      tester,
    ) async {
      final (_, _) = await answered(tester);
      expect(find.byType(InCallScreen), findsOneWidget);
      expect(find.text('SALES · 03 5550 1201'), findsOneWidget);
      expect(find.text('Jordan Price'), findsOneWidget);
      expect(find.text('ENCRYPTED'), findsOneWidget);
      expect(find.text('HD'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor, const Color(0xFF14110F));
      await _end(tester);
    });

    testWidgets(
      'Mute, Hold and Speaker toggle; DTMF from the keypad; hang up',
      (tester) async {
        final (e, id) = await answered(tester);
        await tester.tap(find.bySemanticsLabel('Mute'));
        await _settle(tester);
        expect(e.muted, isTrue);
        await tester.tap(find.bySemanticsLabel('Mute'));
        await _settle(tester);
        expect(e.muted, isFalse);

        await tester.tap(find.bySemanticsLabel('Speaker'));
        await _settle(tester);
        expect(e.audioState.route, AudioRoute.speaker);

        await tester.tap(find.bySemanticsLabel('Hold'));
        await _settle(tester);
        expect(e.activeCalls.single.state, CallState.heldByMe);
        expect(find.text('On hold'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Hold'));
        await _settle(tester);
        expect(e.activeCalls.single.state, CallState.connected);

        await tester.tap(find.bySemanticsLabel('Keypad'));
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel('1'));
        await tester.tap(find.bySemanticsLabel('Hash'));
        await _settle(tester);
        expect(e.dtmfSent[id], '1#');
        await tester.tap(find.text('Hide keypad'));
        await _settle(tester);

        await tester.tap(find.bySemanticsLabel('Hang up'));
        await _settle(tester);
        expect(e.activeCalls, isEmpty);
        expect(find.byType(InCallScreen), findsNothing);
      },
    );

    testWidgets('with Bluetooth, Speaker opens the route sheet', (
      tester,
    ) async {
      final (e, _) = await answered(
        tester,
        routes: {AudioRoute.earpiece, AudioRoute.speaker, AudioRoute.bluetooth},
      );
      await tester.tap(find.bySemanticsLabel(RegExp('^Audio: ')));
      await _settle(tester);
      await tester.tap(find.text('Bluetooth'));
      await _settle(tester);
      expect(e.audioState.route, AudioRoute.bluetooth);
      await _end(tester);
    });

    testWidgets('Add call: first on hold, second call, then Merge', (
      tester,
    ) async {
      final (e, first) = await answered(tester);
      await tester.tap(find.bySemanticsLabel('Add call'));
      await _settle(tester);
      expect(find.byType(KeypadScreen), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Back to the call')), findsOneWidget);
      await _type(tester, '206');
      await tester.tap(find.bySemanticsLabel('Call'));
      await _settle(tester);
      final second = e.called.single;
      expect(second.$1, '206');
      expect(
        e.activeCalls.firstWhere((c) => c.id == first).state,
        CallState.heldByMe,
      );
      final secondId = e.activeCalls.firstWhere((c) => c.id != first).id;
      await tester.runAsync(() async => e.remoteAnswer(secondId));
      await _settle(tester);
      expect(find.bySemanticsLabel(RegExp('on hold. Swap')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Merge'));
      await _settle(tester);
      expect(e.merged, {first, secondId});
      await _end(tester);
    });
  });

  group('Transfer', () {
    Future<(SpyEngine, String)> toTransfer(WidgetTester tester) async {
      usePhone(tester);
      final e = await _engine();
      await tester.pumpWidget(await appUnderTest(engine: e));
      await _settle(tester);
      late String id;
      await tester.runAsync(() async {
        id = e.simulateIncoming(remoteNumber: '+61491570737', info: _westgate);
      });
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Transfer'));
      await _settle(tester);
      return (e, id);
    }

    testWidgets(
      'caller on hold; colleagues with team and presence; Cancel resumes',
      (tester) async {
        final (e, id) = await toTransfer(tester);
        expect(find.byType(TransferScreen), findsOneWidget);
        expect(e.activeCalls.single.state, CallState.heldByMe);
        expect(find.text('Transfer Jordan to'), findsOneWidget);
        expect(find.text('206 · Sales · Available'), findsOneWidget);
        expect(
          find.text('301 · Management · Available on mobile'),
          findsOneWidget,
        );
        expect(find.text('205 · Sales · Do not disturb'), findsOneWidget);
        expect(
          find.text(
            'Talk first lets you introduce the call before handing over.',
          ),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField), 'pri');
        await tester.pump();
        expect(find.text('Priya Shah'), findsOneWidget);
        expect(find.text('Mia Rossi'), findsNothing);
        await tester.tap(find.bySemanticsLabel('Cancel'));
        await _settle(tester);
        expect(find.byType(TransferScreen), findsNothing);
        expect(e.activeCalls.single.state, CallState.connected);
        await _end(tester);
      },
    );

    testWidgets('Send now: blind transfer to the picked colleague', (
      tester,
    ) async {
      final (e, id) = await toTransfer(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Mia Rossi')));
      await tester.pump();
      expect(find.text('Talk to Mia first'), findsOneWidget);
      await tester.tap(find.text('Send now'));
      await _settle(tester);
      expect(e.transferredTo[id], '206');
      expect(e.activeCalls, isEmpty);
      expect(find.byType(VpTabBar), findsOneWidget);
    });

    testWidgets('Talk to Mia first: consult call, then Complete transfer', (
      tester,
    ) async {
      final (e, id) = await toTransfer(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Mia Rossi')));
      await tester.pump();
      await tester.tap(find.text('Talk to Mia first'));
      await _settle(tester);
      expect(e.called.single.$1, '206');
      final consult = e.activeCalls.firstWhere((c) => c.id != id).id;
      await tester.runAsync(() async => e.remoteAnswer(consult));
      await _settle(tester);
      expect(find.byType(InCallScreen), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('on hold, to transfer')),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Complete transfer'));
      await _settle(tester);
      expect(e.transferredTo[id], '206');
      expect(e.activeCalls, isEmpty);
    });

    testWidgets('live presence from the event stream updates a row', (
      tester,
    ) async {
      usePhone(tester);
      final events = StreamController<ServerEvent>.broadcast();
      addTearDown(events.close);
      final live = LiveEvents(
        connect: () => events.stream,
        poll: (_) async => (items: null, etag: null),
      );
      final e = await _engine();
      await tester.pumpWidget(await appUnderTest(engine: e, live: live));
      await _settle(tester);
      await tester.runAsync(
        () async =>
            e.simulateIncoming(remoteNumber: '+61491570737', info: _westgate),
      );
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Answer'));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Transfer'));
      await _settle(tester);
      expect(find.text('206 · Sales · Available'), findsOneWidget);
      expect(
        live.presenceVisible,
        isTrue,
        reason: 'polling fallback while Transfer is open',
      );
      events.add(
        const ServerEvent('presence', {
          'extension': '206',
          'presence': 'on_call',
        }),
      );
      await _settle(tester);
      expect(find.text('206 · Sales · On a call'), findsOneWidget);
      await _end(tester);
    });
  });
  testWidgets('routes: transfer sits under the call it transfers', (
    tester,
  ) async {
    expect(Routes.transfer('x'), '/in-call/x/transfer');
    expect(isCallRoute(Routes.transfer('x')), isTrue);
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(engine: await _engine()));
    await _settle(tester);
    expect(_router(tester), isNotNull);
  });
}
