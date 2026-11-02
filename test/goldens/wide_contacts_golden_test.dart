// FoldContacts at 884 x 1030 (2x): the colleagues, and Priya Shah (picked,
// as on the artboard) beside them with Call 302, Call mobile, her contact
// details and the calls with her; light and dark (dark follows the dark
// tokens; there is no dark Fold artboard), at 3:40 pm on Tuesday 27 October
// in Melbourne. Also the proof widths: 690 (Galaxy Z Fold5 portrait), 680
// at 200% text (the narrowest split), 679 (the list beside the rail), 744
// and 852.
//
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/shell/list_detail.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);

void main() {
  setUpAll(loadAppFonts);

  for (final (name, pref, size, text) in [
    ('light', ThemePreference.light, const Size(884, 1030), 1.0),
    ('dark', ThemePreference.dark, const Size(884, 1030), 1.0),
    ('690_light', ThemePreference.light, const Size(690, 1030), 1.0),
    ('690_dark', ThemePreference.dark, const Size(690, 1030), 1.0),
    ('680_200pct_light', ThemePreference.light, const Size(680, 1030), 2.0),
    ('680_200pct_dark', ThemePreference.dark, const Size(680, 1030), 2.0),
    ('679_light', ThemePreference.light, const Size(679, 1030), 1.0),
    ('744_light', ThemePreference.light, const Size(744, 1030), 1.0),
    ('852_light', ThemePreference.light, const Size(852, 1030), 1.0),
  ]) {
    testWidgets('FoldContacts, $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
      tester.view.viewPadding = const FakeViewPadding(
        top: artboardStatusBar * 2,
      );
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        await appUnderTest(theme: pref, clock: () => _now, api: FakeApi({})),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(VpNavRail),
          matching: find.text('Contacts'),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      final priya = find.descendant(
        of: find.byType(ListDetailLayout),
        matching: find.text('Priya Shah'),
      );
      if (find.byType(ListDetailLayout).evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          priya,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListDetailLayout),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                ),
              )
              .first,
        );
        await tester.ensureVisible(priya);
        await tester.pumpAndSettle();
        await tester.tap(priya);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('contacts_wide_$name.png'),
      );
    });
  }
}
