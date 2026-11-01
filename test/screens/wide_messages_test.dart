// Messages at 600 dp and wider (FoldMessages): the conversations on the
// left, the one picked beside them; and the picked conversation moving
// between its own page (phone) and the pane when the window folds or
// unfolds, with the half-typed reply.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/screens/messages/messages_screen.dart';
import 'package:voiceplatform_app/screens/messages/thread_screen.dart';
import 'package:voiceplatform_app/shell/layout.dart';
import 'package:voiceplatform_app/shell/list_detail.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

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
    expect(list.width, ListDetailLayout.listWidth);
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

  for (final size in [_unfolded, const Size(600, 900), const Size(915, 412)]) {
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
    });
  }

  for (final (width, split) in [(799.0, false), (800.0, true)]) {
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
