// Messages in windows that split (FoldMessages; about 680 dp): the
// left, the one picked beside them; and the picked conversation moving
// between its own page (phone) and the pane when the window folds or
// unfolds, with the half-typed reply.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/screens/messages/messages_screen.dart';
import 'package:voiceplatform_app/screens/messages/thread_screen.dart';
import 'package:voiceplatform_app/shell/layout.dart';
import 'package:voiceplatform_app/shell/list_detail.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/widgets/vp_wide.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);
const _unfolded = Size(884, 1030);
const _phone = Size(390, 844);

void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  addTearDown(tester.view.reset);
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final rail = find.descendant(
    of: find.byType(VpNavRail),
    matching: find.text(label),
  );
  await tester.tap(
    rail.evaluate().isNotEmpty
        ? rail
        : find.descendant(
            of: find.byType(VpTabBar),
            matching: find.text(label),
          ),
  );
  await tester.pumpAndSettle();
}

/// The conversation in the pane beside the list, if any.
String? _paneThread(WidgetTester tester) {
  final v = find.descendant(
    of: find.byType(ListDetailLayout),
    matching: find.byType(ThreadView),
  );
  return v.evaluate().isEmpty ? null : tester.widget<ThreadView>(v).threadId;
}

TextField _reply(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byType(ThreadView),
    matching: find.byType(TextField),
  ),
);

void main() {
  setUpAll(loadAppFonts);
  final olivia = fx.threads[0]['id']! as String;
  final jordan = fx.threads[1]['id']! as String;

  FakeApi api(List<String> read) => FakeApi({
    for (final t in fx.threads)
      'POST /messages/threads/${t['id']}/read': (_) {
        read.add(t['id']! as String);
        return null;
      },
  });

  testWidgets('unfolded: list and the first conversation, left unread', (
    tester,
  ) async {
    _window(tester, _unfolded);
    final read = <String>[];
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api(read)),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    expect(find.byType(ListDetailLayout), findsOneWidget);
    expect(_paneThread(tester), olivia);
    expect(read, isEmpty, reason: 'shown, not picked');
    final list = tester.getRect(
      find
          .descendant(
            of: find.byType(ListDetailLayout),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(list.width, listMaxWidth);
    expect(find.text('From Sales mobile 0491 571 266'), findsOneWidget);
  });

  testWidgets('picking a conversation shows it and marks it read', (
    tester,
  ) async {
    _window(tester, _unfolded);
    final read = <String>[];
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api(read)),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    await tester.tap(find.text('Jordan Price').first);
    await tester.pumpAndSettle();
    expect(_paneThread(tester), jordan);
    await tester.tap(find.text('Olivia Chen').first);
    await tester.pumpAndSettle();
    expect(_paneThread(tester), olivia);
    expect(read, [olivia]);
  });

  testWidgets('phone, then unfold, then fold: the conversation and the '
      'half-typed reply follow', (tester) async {
    _window(tester, _phone);
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api([])),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    await tester.tap(find.text('Olivia Chen'));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadScreen), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(ThreadView),
        matching: find.byType(TextField),
      ),
      'Sure, sending',
    );
    await tester.pump();

    await _resize(tester, _unfolded);
    expect(find.byType(ThreadScreen), findsNothing);
    expect(find.byType(MessagesScreen), findsOneWidget);
    expect(_paneThread(tester), olivia);
    expect(_reply(tester).controller!.text, 'Sure, sending');

    await _resize(tester, _phone);
    expect(find.byType(ThreadScreen), findsOneWidget);
    expect(_reply(tester).controller!.text, 'Sure, sending');

    // Back to the list: nothing picked any more.
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadScreen), findsNothing);
    await _resize(tester, _unfolded);
    expect(_paneThread(tester), olivia, reason: 'the first, as shown');
    await _resize(tester, _phone);
    expect(find.byType(ThreadScreen), findsNothing, reason: 'not picked');
  });

  testWidgets('unfolded, picked, then fold on another tab: no thread opens '
      'over it', (tester) async {
    _window(tester, _unfolded);
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api([])),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    await tester.tap(find.text('Jordan Price').first);
    await tester.pumpAndSettle();
    await _openTab(tester, 'Contacts');
    await _resize(tester, _phone);
    expect(find.byType(ThreadScreen), findsNothing);
  });

  for (final size in [
    _unfolded,
    const Size(679, 900),
    const Size(680, 900),
    const Size(690, 900),
    const Size(744, 900),
    const Size(852, 900),
    const Size(600, 900),
    const Size(915, 412),
  ]) {
    testWidgets('text at 200% stays in its boxes, '
        '${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
      _window(tester, size);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        await appUnderTest(clock: () => _now, api: api([])),
      );
      await tester.pumpAndSettle();
      await _openTab(tester, 'Messages');
      expect(tester.takeException(), isNull);
      expect(
        _paneThread(tester),
        size.width >= listDetailMinWidth ? olivia : null,
      );
      if (size.width < listDetailMinWidth || size.height < 600) return;
      // The reply box fits the pane: typed text, the send button and the
      // count all inside it, nothing past its box.
      final pane = tester.getRect(find.byType(ThreadView));
      await tester.enterText(
        find.descendant(
          of: find.byType(ThreadView),
          matching: find.byType(TextField),
        ),
        'Sure, sending it now.',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final f in [
        find.descendant(
          of: find.byType(ThreadView),
          matching: find.byType(TextField),
        ),
        find.bySemanticsLabel('Send'),
        find.text('21 of 160 characters · 1 part'),
        find.text('From Sales mobile 0491 571 266'),
      ]) {
        final r = tester.getRect(f.last);
        expect(r.left, greaterThanOrEqualTo(pane.left), reason: '$f');
        expect(r.right, lessThanOrEqualTo(pane.right), reason: '$f');
        expect(r.bottom, lessThanOrEqualTo(pane.bottom), reason: '$f');
      }
    });
  }

  for (final (width, split) in [(679.0, false), (680.0, true)]) {
    testWidgets('${width.toInt()} dp: '
        '${split ? 'list and detail' : 'the list, then the conversation'}', (
      tester,
    ) async {
      _window(tester, Size(width, 900));
      await tester.pumpWidget(
        await appUnderTest(clock: () => _now, api: api([])),
      );
      await tester.pumpAndSettle();
      await _openTab(tester, 'Messages');
      expect(find.byType(VpNavRail), findsOneWidget);
      expect(
        find.byType(ListDetailLayout),
        split ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('Jordan Price').first);
      await tester.pumpAndSettle();
      expect(find.byType(ThreadScreen), split ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  Finder replyBox() => find.descendant(
    of: find.byType(ThreadView),
    matching: find.byType(TextField),
  );

  testWidgets('a reply that sends while another conversation is open never '
      'comes back to send again', (tester) async {
    _window(tester, _unfolded);
    final sent = Completer<Object?>();
    await tester.pumpWidget(
      await appUnderTest(
        clock: () => _now,
        api: FakeApi({
          for (final t in fx.threads)
            'POST /messages/threads/${t['id']}/read': (_) => null,
          'POST /messages/send': (_) => sent.future,
        }),
      ),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    await tester.tap(find.text('Olivia Chen').first);
    await tester.pumpAndSettle();
    await tester.enterText(replyBox(), 'Sending it now');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    // Another conversation before the send answers: the first view goes.
    await tester.tap(find.text('Jordan Price').first);
    await tester.pumpAndSettle();
    expect(_paneThread(tester), jordan);
    sent.complete({
      'id': 'm9',
      'threadId': olivia,
      'direction': 'out',
      'at': '2026-10-27T04:40:00Z',
      'kind': 'text',
      'text': 'Sending it now',
      'senderName': 'Ava',
      'status': 'queued',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olivia Chen').first);
    await tester.pumpAndSettle();
    expect(_paneThread(tester), olivia);
    expect(_reply(tester).controller!.text, isEmpty);
  });

  Map<String, Object?> sentMessage(String text) => {
    'id': 'm9',
    'threadId': olivia,
    'direction': 'out',
    'at': '2026-10-27T04:40:00Z',
    'kind': 'text',
    'text': text,
    'senderName': 'Ava',
    'status': 'queued',
  };

  // What the person does in the box while it sends: nothing, adds to the
  // end of the sent words (the rest stays, to send next), or rewrites it
  // (it stays as it is).
  const meanwhile = {
    'nothing': (typed: null, left: ''),
    'appended': (typed: 'Sending it now, see you at 3', left: ', see you at 3'),
    'appended on a new line': (
      typed: 'Sending it now\nSee you at 3',
      left: 'See you at 3',
    ),
    'rewritten': (typed: 'And one more thing', left: 'And one more thing'),
  };

  Future<Completer<Object?>> sendingApp(WidgetTester tester, Size at) async {
    _window(tester, at);
    final sent = Completer<Object?>();
    await tester.pumpWidget(
      await appUnderTest(
        clock: () => _now,
        api: FakeApi({
          for (final t in fx.threads)
            'POST /messages/threads/${t['id']}/read': (_) => null,
          'POST /messages/send': (_) => sent.future,
        }),
      ),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    return sent;
  }

  void expectCursorAtEnd(WidgetTester tester) {
    final v = _reply(tester).controller!.value;
    expect(v.selection, TextSelection.collapsed(offset: v.text.length));
  }

  for (final MapEntry(key: what, value: m) in meanwhile.entries) {
    testWidgets('unfold during a send, $what meanwhile: the new box keeps '
        'only what was not sent', (tester) async {
      final sent = await sendingApp(tester, _phone);
      await tester.tap(find.text('Olivia Chen'));
      await tester.pumpAndSettle();
      await tester.enterText(replyBox(), 'Sending it now');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();

      // Unfold while it sends: a new box, beside the list, with the text.
      await _resize(tester, _unfolded);
      expect(find.byType(ThreadScreen), findsNothing);
      expect(_paneThread(tester), olivia);
      expect(_reply(tester).controller!.text, 'Sending it now');
      if (m.typed != null) {
        await tester.enterText(replyBox(), m.typed!);
        await tester.pump();
      }

      sent.complete(sentMessage('Sending it now'));
      await tester.pumpAndSettle();
      expect(_reply(tester).controller!.text, m.left);
      expectCursorAtEnd(tester);
    });

    testWidgets('fold during a send, $what meanwhile: the phone box keeps '
        'only what was not sent', (tester) async {
      final sent = await sendingApp(tester, _unfolded);
      await tester.enterText(replyBox(), 'Sending it now');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await _resize(tester, _phone);
      expect(find.byType(ThreadScreen), findsOneWidget);
      expect(_reply(tester).controller!.text, 'Sending it now');
      if (m.typed != null) {
        await tester.enterText(replyBox(), m.typed!);
        await tester.pump();
      }
      sent.complete(sentMessage('Sending it now'));
      await tester.pumpAndSettle();
      expect(_reply(tester).controller!.text, m.left);
      expectCursorAtEnd(tester);
    });
  }

  testWidgets('adding to the end while it sends, in the same box: the sent '
      'words go, the rest stays with the cursor where it was', (tester) async {
    final sent = await sendingApp(tester, _unfolded);
    await tester.enterText(replyBox(), 'Sending it now');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    // Still typing: the cursor sits after "see", before " you at 3".
    _reply(tester).controller!.value = const TextEditingValue(
      text: 'Sending it now, see you at 3',
      selection: TextSelection.collapsed(offset: 19),
    );
    await tester.pump();
    sent.complete(sentMessage('Sending it now'));
    await tester.pumpAndSettle();
    final v = _reply(tester).controller!.value;
    expect(v.text, ', see you at 3');
    expect(v.selection, const TextSelection.collapsed(offset: 5));
    // Typing carries on from there.
    await tester.enterText(replyBox(), ', see you at 3:30');
    await tester.pump();
    expect(_reply(tester).controller!.text, ', see you at 3:30');
  });

  testWidgets('typing in the shown conversation picks it: read, and a fold '
      'opens it', (tester) async {
    _window(tester, _unfolded);
    final read = <String>[];
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api(read)),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    expect(read, isEmpty);
    await tester.enterText(replyBox(), 'On it');
    await tester.pumpAndSettle();
    expect(read, [olivia]);
    expect(_reply(tester).controller!.text, 'On it', reason: 'kept typing');
    await _resize(tester, _phone);
    expect(find.byType(ThreadScreen), findsOneWidget);
    expect(_reply(tester).controller!.text, 'On it');
  });

  testWidgets('focusing the reply box picks the shown conversation', (
    tester,
  ) async {
    _window(tester, _unfolded);
    final read = <String>[];
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api(read)),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    await tester.tap(replyBox());
    await tester.pumpAndSettle();
    expect(read, [olivia]);
  });

  testWidgets('the line pill shows in full when there is room', (tester) async {
    _window(tester, _unfolded);
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api([])),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    for (final p in tester.widgetList<VpOffPill>(find.byType(VpOffPill))) {
      final text = find.descendant(
        of: find.byWidget(p),
        matching: find.text(p.text),
      );
      final para = tester.renderObject<RenderParagraph>(text);
      expect(para.didExceedMaxLines, isFalse, reason: p.text);
    }
  });

  testWidgets('the list keeps its place across the split switch (680 dp)', (
    tester,
  ) async {
    _window(tester, const Size(700, 420));
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api([])),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    final listView = find.byWidgetPredicate(
      (w) => w is ListView && w.key == const PageStorageKey('messages-threads'),
    );
    final scrollable = find
        .descendant(of: listView, matching: find.byType(Scrollable))
        .first;
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(before, greaterThan(0));
    await _resize(tester, const Size(679, 420));
    final after = tester
        .state<ScrollableState>(
          find
              .descendant(of: listView, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    expect(after.pixels, greaterThan(0));
    expect(after.pixels, before.clamp(0, after.maxScrollExtent));
  });

  for (final size in [_phone, const Size(360, 800)]) {
    testWidgets('phone, 200% text: the count under the reply box fits, '
        '${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
      _window(tester, size);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        await appUnderTest(clock: () => _now, api: api([])),
      );
      await tester.pumpAndSettle();
      await _openTab(tester, 'Messages');
      await tester.tap(find.text('Olivia Chen'));
      await tester.pumpAndSettle();
      await tester.enterText(replyBox(), 'Sure, sending it now.');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final count = tester.getRect(find.text('21 of 160 characters · 1 part'));
      expect(count.right, lessThanOrEqualTo(size.width));
      expect(count.bottom, lessThanOrEqualTo(size.height));
    });
  }

  testWidgets('screen reader: rows are buttons with selected state', (
    tester,
  ) async {
    _window(tester, _unfolded);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      await appUnderTest(clock: () => _now, api: api([])),
    );
    await tester.pumpAndSettle();
    await _openTab(tester, 'Messages');
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^1 unread. Olivia'))),
      matchesSemantics(
        label: tester
            .getSemantics(find.bySemanticsLabel(RegExp('^1 unread. Olivia')))
            .label,
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(find.bySemanticsLabel('Call'), findsOneWidget);
    expect(find.bySemanticsLabel('New message'), findsOneWidget);
    handle.dispose();
  });
}
