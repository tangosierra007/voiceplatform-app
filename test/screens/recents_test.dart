// AppRecents and AppVoicemail on the canvas sample data.
import 'dart:io';

import 'package:call_engine/call_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/features/recents/greetings.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/screens/recents/greeting_screen.dart';
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

Finder _buttonStarting(String label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      (w.properties.label ?? '').startsWith(label),
);

FakeApi _api() => FakeApi({
  for (final v in fx.voicemails)
    'POST /voicemail/messages/${v['id']}/media-url': (_) => {
      'url': '/app/v1/media/token-${v['id']}',
      'expiresAt': '2026-10-27T00:15:00.000Z',
    },
  for (final v in fx.voicemails) ...{
    'POST /voicemail/messages/${v['id']}/read': (_) => null,
    'POST /voicemail/messages/${v['id']}/delete': (_) => null,
  },
});

void main() {
  setUpAll(loadAppFonts);

  Future<FakeCallEngine> engine() async {
    final e = FakeCallEngine(
      outgoing: OutgoingScript.manual,
      registerAfter: Duration.zero,
    );
    await e.start();
    await e.register(_account);
    return e;
  }

  Future<void> openRecents(WidgetTester tester) async {
    await tester.tap(_tab('Recents'));
    await _settle(tester);
  }

  testWidgets('Recents lists the calls as the artboard; opening marks seen', (
    tester,
  ) async {
    usePhone(tester);
    var seen = 0;
    await tester.pumpWidget(
      await appUnderTest(onHistorySeen: () async => seen++),
    );
    await _settle(tester);
    await openRecents(tester);
    expect(seen, 1);
    for (final t in [
      'All',
      'Missed 2',
      'Voicemail 2',
      'Mine only',
      'Westgate Supplies',
      'Missed · left voicemail',
      'Jordan Price',
      'Incoming · 4:12',
      '0491 570 110',
      'Answered by Mia on her desk phone',
      'Priya Shah',
      'Outgoing · 1:37',
      'Chris Doyle',
      'Incoming · 0:51',
      '03 5550 1142',
      'Outgoing · 6:20',
      'Private',
      'Missed',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Missed calls in the alert colour.
    final westgate = tester.widget<Text>(find.text('Westgate Supplies'));
    final jordan = tester.widget<Text>(find.text('Jordan Price'));
    expect(westgate.style!.color, isNot(jordan.style!.color));
  });

  testWidgets('Missed and Mine only filter the list', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest());
    await _settle(tester);
    await openRecents(tester);
    await tester.tap(find.text('Missed 2'));
    await _settle(tester);
    expect(find.text('Westgate Supplies'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Jordan Price'), findsNothing);
    await tester.tap(find.text('Mine only'));
    await _settle(tester);
    expect(find.text('Priya Shah'), findsOneWidget);
    expect(find.text('Westgate Supplies'), findsNothing);
  });

  testWidgets('tapping a row calls back; Private has nothing to call', (
    tester,
  ) async {
    usePhone(tester);
    final e = await engine();
    await tester.pumpWidget(await appUnderTest(engine: e));
    await _settle(tester);
    await openRecents(tester);
    expect(_buttonStarting('Call back Private'), findsNothing);
    await tester.tap(_buttonStarting('Call back Jordan Price'));
    await _settle(tester);
    expect(e.activeCalls.single.remoteNumber, '+61491570737');
    await tester.pumpWidget(const SizedBox());
    await e.dispose();
  });

  testWidgets('a phone contact names a number on this device only', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(
      await appUnderTest(
        phoneContacts: const [
          PhoneContact('Kim Bell', ['03 5550 1142']),
        ],
      ),
    );
    await _settle(tester);
    await openRecents(tester);
    expect(find.text('Kim Bell'), findsOneWidget);
    expect(find.text('03 5550 1142'), findsNothing);
  });

  testWidgets('details sheet: Call back and Play voicemail', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest());
    await _settle(tester);
    await openRecents(tester);
    await tester.tap(_button('Details for Westgate Supplies'));
    await _settle(tester);
    expect(find.text('To the Sales line'), findsOneWidget);
    await tester.tap(_button('Play voicemail'));
    await _settle(tester);
    // The voicemail view, with the message open in the player.
    expect(find.text('All boxes'), findsOneWidget);
    expect(find.text('Westgate Supplies'), findsOneWidget);
    expect(_button('Play'), findsOneWidget);
  });

  testWidgets('Voicemail: boxes with counts, the player, the other messages', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest());
    await _settle(tester);
    await openRecents(tester);
    await tester.tap(find.text('Voicemail 2'));
    await _settle(tester);
    for (final t in [
      'Greeting',
      'All boxes',
      'Mine',
      'Sales 1',
      'Rentals 1',
      'Westgate Supplies',
      '03 5550 1987',
      '0:00',
      '1:15',
      'Call back',
      'Speaker',
      'Chris Doyle',
      '0491 571 804 · Mine box',
      'Dana Ho',
      '0491 572 665 · Mine box',
      '0491 574 632',
      'Rentals box',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(_button('Delete'), findsOneWidget);
    // One box at a time.
    await tester.tap(find.text('Rentals 1'));
    await _settle(tester);
    expect(find.text('Westgate Supplies'), findsNothing);
    expect(find.text('Rentals box'), findsNothing); // its number is the title
    expect(find.text('0491 574 632'), findsOneWidget);
  });

  testWidgets(
    'Play streams a fresh signed URL each time and marks the message heard',
    (tester) async {
      usePhone(tester);
      final api = _api();
      final player = FakeMediaPlayer();
      await tester.pumpWidget(
        await appUnderTest(api: api, player: player, accessToken: 'tok-1'),
      );
      await _settle(tester);
      await openRecents(tester);
      await tester.tap(find.text('Voicemail 2'));
      await _settle(tester);
      await tester.tap(_button('Play'));
      await _settle(tester);
      final westgate = fx.voicemails.first['id'];
      expect(player.opened, hasLength(1));
      final (url, headers) = player.opened.single;
      expect(url.toString(), 'http://127.0.0.1:9/app/v1/media/token-$westgate');
      expect(headers['Authorization'], 'Bearer tok-1');
      expect(headers['X-VP-App'], 'android/1.0.0');
      expect(player.speaker, [false]); // the earpiece until Speaker
      expect(
        api.requests.map((r) => r.toString()),
        containsAll([
          'POST /voicemail/messages/$westgate/media-url',
          'POST /voicemail/messages/$westgate/read',
        ]),
      );
      expect(
        api.requests
            .firstWhere((r) => r.path.endsWith('/read'))
            .body
            .replaceAll(' ', ''),
        '{"heard":true}',
      );
      // Pause, then Speaker.
      await tester.tap(_button('Pause'));
      await _settle(tester);
      expect(player.state.playing, isFalse);
      await tester.tap(_button('Speaker'));
      await _settle(tester);
      expect(player.speaker.last, isTrue);
      // Another message asks for its own URL.
      await tester.tap(_buttonStarting('Chris Doyle'));
      await _settle(tester);
      await tester.tap(_button('Play'));
      await _settle(tester);
      expect(player.opened, hasLength(2));
      expect(
        api.requests.where((r) => r.path.endsWith('/media-url')),
        hasLength(2),
      );
    },
  );

  testWidgets('Delete asks first; legal hold says why it stays', (
    tester,
  ) async {
    usePhone(tester);
    final api = _api();
    final westgate = fx.voicemails.first['id'];
    api.routes['POST /voicemail/messages/$westgate/delete'] = (_) =>
        (409, {'error': 'legal_hold', 'message': 'held'});
    await tester.pumpWidget(await appUnderTest(api: api));
    await _settle(tester);
    await openRecents(tester);
    await tester.tap(find.text('Voicemail 2'));
    await _settle(tester);
    await tester.tap(_button('Delete'));
    await _settle(tester);
    expect(find.text('Delete this voicemail?'), findsOneWidget);
    expect(
      find.text(
        'The message from Westgate Supplies goes for everyone who shares the '
        'Sales box.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await _settle(tester);
    expect(
      find.text("This voicemail is kept on hold, so it can't be deleted."),
      findsOneWidget,
    );
  });

  testWidgets('Greeting lists the three greetings and records one', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest());
    await _settle(tester);
    await openRecents(tester);
    await tester.tap(find.text('Voicemail 2'));
    await _settle(tester);
    await tester.tap(_button('Greeting'));
    await _settle(tester);
    expect(find.byType(GreetingScreen), findsOneWidget);
    expect(find.text("When I can't answer"), findsOneWidget);
    expect(find.text('Your recording · 0:09'), findsOneWidget);
    expect(find.text("When I'm on a call"), findsOneWidget);
    expect(find.text('The standard greeting'), findsOneWidget);
    expect(find.text('My name'), findsOneWidget);
    expect(find.text('Your recording · 0:02'), findsOneWidget);
    // The tab bar stays: Greeting is inside Recents.
    expect(find.byType(VpTabBar), findsOneWidget);
  });

  test('a failed greeting upload keeps the recording for a retry', () async {
    final dir = Directory.systemTemp.createTempSync('greeting');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/g.m4a')..writeAsBytesSync([1, 2, 3]);
    var fail = true;
    final api = FakeApi({
      'PUT /voicemail/greetings/busy': (_) => fail
          ? (500, {'error': 'x', 'message': 'x'})
          : {'kind': 'busy', 'isCustom': true, 'durationSeconds': 3},
    });
    final c = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9/app/v1'))
            ..httpClientAdapter = api,
        ),
      ],
    );
    addTearDown(c.dispose);
    final upload = c.read(greetingUploadProvider);
    await expectLater(
      upload(GreetingKind.busy, file),
      throwsA(isA<DioException>()),
    );
    expect(file.existsSync(), isTrue);
    fail = false;
    final g = await upload(GreetingKind.busy, file);
    expect(g.isCustom, isTrue);
    expect(file.existsSync(), isFalse);
    expect(api.requests.last.headers['content-type'], 'audio/mp4');
  });
}
