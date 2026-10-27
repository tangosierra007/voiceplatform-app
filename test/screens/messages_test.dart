// AppMessages and AppThread on the canvas sample data; SMS part counting;
// a `message` push refreshes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/calls/numbers.dart';
import 'package:voiceplatform_app/engine/phone_extras.dart';
import 'package:voiceplatform_app/engine/push_handler.dart';
import 'package:voiceplatform_app/features/messages/messages_data.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/screens/messages/thread_screen.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

final _now = DateTime.utc(2026, 10, 27, 4, 40); // 3:40 pm in Melbourne

String _at(String iso) => clockTime(DateTime.parse(iso).toLocal());

void main() {
  setUpAll(loadAppFonts);

  group('SMS parts', () {
    test('GSM-7: 160 in one part, then 153 a part', () {
      expect(smsCount('a' * 160).parts, 1);
      expect(smsCount('a' * 161).parts, 2);
      expect(smsCount('a' * 306).parts, 2);
      expect(smsCount('a' * 307).parts, 3);
      // Extension characters take two.
      expect(smsCount('€' * 80).units, 160);
      expect(smsCount('€' * 81).parts, 2);
      expect(smsCount('a' * 160).unicode, isFalse);
    });

    test('UCS-2: 70 in one part, then 67 a part', () {
      expect(smsCount('ā' * 70).parts, 1);
      expect(smsCount('ā' * 71).parts, 2);
      expect(smsCount('ā' * 134).parts, 2);
      expect(smsCount('ā' * 135).parts, 3);
      expect(smsCount('😀').units, 2);
      expect(smsCount('😀').unicode, isTrue);
    });

    test('packed part by part: no character split across parts (WS6)', () {
      // 306 septets would be 2 parts, but the euro sign can't straddle.
      expect(smsCount('${'a' * 152}€${'a' * 152}').parts, 3);
      // 134 code units would be 2 parts, but the surrogate pair can't.
      expect(smsCount('${'a' * 66}😀${'a' * 66}').parts, 3);
      // At the limit: ten parts of 76 euros (152 septets) send; one more euro
      // needs an eleventh. 33 emoji fill a UCS-2 part.
      expect(smsCount('€' * 760).parts, 10);
      expect(smsCount('€' * 760).tooLong, isFalse);
      expect(smsCount('${'€' * 760}a').parts, 10);
      expect(smsCount('€' * 761).tooLong, isTrue);
      expect(smsCount('😀' * 330).parts, 10);
      expect(smsCount('😀' * 331).tooLong, isTrue);
    });

    test('more than 10 parts is refused', () {
      expect(smsCount('a' * (153 * 10)).tooLong, isFalse);
      expect(smsCount('a' * (153 * 10 + 1)).tooLong, isTrue);
      expect(smsCount('ā' * (67 * 10 + 1)).tooLong, isTrue);
      expect(smsCountText(smsCount('a' * 42)), '42 / 160');
      expect(smsCountText(smsCount('a' * 200)), '200 / 306 · 2 parts');
    });
  });

  testWidgets('Messages lists the threads as the artboard', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(await appUnderTest(clock: () => _now));
    await _settle(tester);
    await tester.tap(_tab('Messages'));
    await _settle(tester);
    for (final t in [
      'All',
      'Sales mobile',
      'Service mobile',
      'Olivia Chen',
      'Perfect, can you email it to me as well?',
      'Jordan Price',
      'You: Delivery booked for Thursday morning',
      'Dana Ho',
      'Sent a picture message (not shown yet)',
      'Yesterday',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.bySemanticsLabel('New message'), findsOneWidget);
    expect(
      find.textContaining('WhatsApp, coming later.', findRichText: true),
      findsOneWidget,
    );
    // A line chip filters.
    await tester.tap(find.text('Service mobile').first);
    await _settle(tester);
    expect(find.text('Olivia Chen'), findsNothing);
    expect(find.text('Dana Ho'), findsOneWidget);
  });

  testWidgets('Thread: who sent, delivered, from which line, the counter', (
    tester,
  ) async {
    usePhone(tester);
    final api = FakeApi({
      'POST /messages/threads/${fx.threads.first['id']}/read': (_) => null,
    });
    await tester.pumpWidget(await appUnderTest(clock: () => _now, api: api));
    await _settle(tester);
    await tester.tap(_tab('Messages'));
    await _settle(tester);
    await tester.tap(find.text('Olivia Chen'));
    await _settle(tester);
    expect(find.byType(ThreadScreen), findsOneWidget);
    expect(find.byType(VpTabBar), findsNothing);
    final msgs = fx.threadMessages[fx.threads.first['id']]!;
    expect(find.text('Texting Sales mobile'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.text('Ava · ${_at(msgs[0]['at']! as String)} · Delivered'),
      findsOneWidget,
    );
    expect(find.text(_at(msgs[1]['at']! as String)), findsOneWidget);
    expect(find.text('From Sales mobile 0491 571 266'), findsOneWidget);
    expect(find.bySemanticsLabel('Call Olivia Chen'), findsOneWidget);
    // Opening an unread thread marks it read.
    expect(api.requests.map((r) => r.toString()), [
      'POST /messages/threads/${fx.threads.first['id']}/read',
    ]);

    await tester.enterText(find.byType(TextField), 'See you Thursday');
    await _settle(tester);
    expect(find.text('16 / 160'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a' * 1531);
    await _settle(tester);
    expect(find.text('11 parts, up to 10. Shorten to send.'), findsOneWidget);
    final send = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Send',
      ),
    );
    expect(send.properties.enabled, isFalse);
  });

  testWidgets('Send posts the text from the thread line', (tester) async {
    usePhone(tester);
    final olivia = fx.threads.first;
    final api = FakeApi({
      'POST /messages/threads/${olivia['id']}/read': (_) => null,
      'POST /messages/send': (_) => {
        'id': 'm9',
        'threadId': olivia['id'],
        'direction': 'out',
        'at': '2026-10-27T04:40:00Z',
        'kind': 'text',
        'text': 'See you Thursday',
        'senderName': 'Ava',
        'status': 'queued',
      },
    });
    await tester.pumpWidget(await appUnderTest(clock: () => _now, api: api));
    await _settle(tester);
    await tester.tap(_tab('Messages'));
    await _settle(tester);
    await tester.tap(find.text('Olivia Chen'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'See you Thursday');
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Send'));
    await _settle(tester);
    final sent = api.requests.where((r) => r.path == '/messages/send').single;
    expect(sent.body, contains('"lineId":"${olivia['lineId']}"'));
    expect(sent.body, contains('"to":"${olivia['number']}"'));
    expect(sent.body, contains('"text":"See you Thursday"'));
  });

  test('a message push refetches the threads and the badge', () async {
    var fetched = 0;
    final extras = FakeExtras();
    final c = ProviderContainer(
      overrides: [
        phoneExtrasProvider.overrideWithValue(extras),
        threadsProvider.overrideWith((ref, line) async {
          fetched++;
          return fixtureThreads(lineId: line);
        }),
        meProvider.overrideWith((ref) async => null),
        liveEventsProvider.overrideWithValue(quietLiveEvents()),
      ],
    );
    addTearDown(c.dispose);
    c.read(pushHandlerProvider);
    final sub = c.listen(threadsProvider(null), (_, _) {});
    await c.read(threadsProvider(null).future);
    expect(fetched, 1);
    extras.push(VpPushType.message);
    await Future<void>.delayed(Duration.zero);
    await c.read(threadsProvider(null).future);
    expect(fetched, 2);
    sub.close();
  });
}
