// FoldMessages at 884 x 1030 (2x): the conversations and Olivia Chen's
// thread beside them, light and dark (dark follows the dark tokens; there
// is no dark Fold artboard), at 3:40 pm on Tuesday 27 October in Melbourne.
// Typing in the shown conversation picks it ("Sure, sending it now."), as
// on the artboard. Also 690 x 1030 (Galaxy Z Fold5 portrait), and 680 x 1030
// at 200% text, the narrowest split.
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

  for (final (name, pref, size, scale) in [
    ('light', ThemePreference.light, const Size(884, 1030), 1.0),
    ('dark', ThemePreference.dark, const Size(884, 1030), 1.0),
    // A Galaxy Z Fold5 unfolded in portrait (690 dp): the list narrows.
    ('690_light', ThemePreference.light, const Size(690, 1030), 1.0),
    ('690_dark', ThemePreference.dark, const Size(690, 1030), 1.0),
    // The narrowest split (680 dp) at 200% text: the reply box and the
    // count fit.
    ('680_200pct_light', ThemePreference.light, const Size(680, 1030), 2.0),
    ('680_200pct_dark', ThemePreference.dark, const Size(680, 1030), 2.0),
  ]) {
    testWidgets('FoldMessages, $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
