// The voicemail counts (TJ's A53 run, 2 Nov): the Recents "Voicemail" chip,
// the box counts and the tab badge follow a play (heard), a mark as new and
// a delete at once, then the server. A refused change leaves the counts as
// the server has them, and a refused heard is asked again on the next play.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Finder _button(String label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      w.properties.label == label,
);

Finder _row(String start) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.button == true &&
      (w.properties.label ?? '').startsWith(start),
);

/// The Voicemail filter chip's text: "Voicemail 2", or "Voicemail" for none.
String _chip(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .firstWhere((s) => RegExp(r'^Voicemail( \d+)?$').hasMatch(s));

/// The Recents tab's badge, from its screen reader label.
bool _badge(WidgetTester t, int n) => find
    .descendant(
      of: find.byType(VpTabBar),
      matching: find.bySemanticsLabel(
        n == 0 ? RegExp(r'^Recents$') : RegExp('^Recents, $n new'),
      ),
    )
    .evaluate()
    .isNotEmpty;

Future<VoicemailServer> _open(WidgetTester tester) async {
  usePhone(tester);
  final server = VoicemailServer();
  await tester.pumpWidget(
    await appUnderTest(
      api: FakeApi(server.routes),
      player: FakeMediaPlayer(),
      voicemail: server,
      status: null,
    ),
  );
  await _settle(tester);
  await tester.tap(
    find.descendant(of: find.byType(VpTabBar), matching: find.text('Recents')),
  );
  await _settle(tester);
  await tester.tap(find.text('Voicemail 2'));
  await _settle(tester);
  return server;
}

Future<void> _delete(WidgetTester tester) async {
  await tester.tap(_button('Delete'));
  await _settle(tester);
  await tester.tap(find.widgetWithText(TextButton, 'Delete'));
  await _settle(tester);
}

void main() {
  setUpAll(loadAppFonts);
  final westgate = fx.voicemails[0]['id']! as String;

  testWidgets('play: the counts drop by one at once, then from the server', (
    tester,
  ) async {
    final server = await _open(tester);
    expect(_chip(tester), 'Voicemail 2');
    expect(find.text('Sales 1'), findsOneWidget);
    expect(_badge(tester, 2), isTrue);

    final held = Completer<void>();
    server.hold = held;
    await tester.tap(_button('Play'));
    await _settle(tester);
    // Before the server answers.
    expect(_chip(tester), 'Voicemail 1');
    expect(find.text('Sales 1'), findsNothing);
    expect(find.text('Sales'), findsOneWidget);
    expect(_badge(tester, 1), isTrue);

    held.complete();
    await _settle(tester);
    expect(server.heard[westgate], isTrue);
    expect(_chip(tester), 'Voicemail 1');
    expect(find.text('Rentals 1'), findsOneWidget);
    expect(_badge(tester, 1), isTrue);
  });

  testWidgets('delete one of two new: 1; delete the last: no count', (
    tester,
  ) async {
    final server = await _open(tester);
    // The open message is Westgate's (new).
    await _delete(tester);
    expect(server.deleted, {westgate});
    expect(_chip(tester), 'Voicemail 1');
    expect(_badge(tester, 1), isTrue);
    // The other new one is the Rentals box's.
    await tester.tap(find.text('Rentals 1'));
    await _settle(tester);
    await _delete(tester);
    expect(_chip(tester), 'Voicemail');
    expect(find.text('Rentals'), findsOneWidget);
    expect(_badge(tester, 0), isTrue);
  });

  testWidgets('mark as new: the counts rise', (tester) async {
    await _open(tester);
    await tester.longPress(_row('Chris Doyle'));
    await _settle(tester);
    expect(_chip(tester), 'Voicemail 3');
    expect(find.text('Mine 1'), findsOneWidget);
    expect(_badge(tester, 3), isTrue);
  });

  testWidgets('a refused heard: back to the server\'s counts, still new, '
      'asked again on the next play', (tester) async {
    final server = await _open(tester);
    server.failNext = true;
    await tester.tap(_button('Play'));
    await _settle(tester);
    expect(server.heard[westgate], isFalse);
    expect(_chip(tester), 'Voicemail 2');
    expect(find.text('Sales 1'), findsOneWidget);
    expect(_badge(tester, 2), isTrue);

    // Play another, then Westgate's again: loading it afresh asks again.
    await tester.tap(_button('Pause'));
    await _settle(tester);
    await tester.tap(_row('Chris Doyle'));
    await _settle(tester);
    await tester.tap(_button('Play'));
    await _settle(tester);
    await tester.tap(_row('New. Westgate Supplies'));
    await _settle(tester);
    await tester.tap(_button('Play'));
    await _settle(tester);
    expect(server.heard[westgate], isTrue);
    expect(_chip(tester), 'Voicemail 1');
  });

  testWidgets('a refused delete: the counts are the server\'s again', (
    tester,
  ) async {
    final server = await _open(tester);
    server.failNext = true;
    await _delete(tester);
    expect(server.deleted, isEmpty);
    expect(_chip(tester), 'Voicemail 2');
    expect(find.text("It didn't delete. Try again."), findsOneWidget);
  });
}
