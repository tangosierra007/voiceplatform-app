// FoldMessages at 884 x 1030 (2x): the conversations and Olivia Chen's
// thread beside them, light and dark (dark follows the dark tokens; there
// is no dark Fold artboard), at 3:40 pm on Tuesday 27 October in Melbourne.
// Picked, as on the artboard, with "Sure, sending it now." half typed.
//
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/screens/messages/thread_screen.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);

void main() {
  setUpAll(loadAppFonts);

  for (final (name, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('FoldMessages, $name, 884 x 1030', (tester) async {
      tester.view.physicalSize = const Size(884, 1030) * 2;
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
      tester.view.viewPadding = const FakeViewPadding(
        top: artboardStatusBar * 2,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        await appUnderTest(
          theme: pref,
          clock: () => _now,
          api: FakeApi({
            'POST /messages/threads/${fx.threads.first['id']}/read': (_) =>
                null,
          }),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(VpNavRail),
          matching: find.text('Messages'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(ThreadView),
          matching: find.byType(TextField),
        ),
        'Sure, sending it now.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('messages_wide_$name.png'),
      );
    });
  }
}
