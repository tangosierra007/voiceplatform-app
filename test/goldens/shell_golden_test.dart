// Goldens at the artboards' 390 x 844 (rendered at 2x), light and dark, with
// the bundled fonts. The tab bar golden is compared with AppKeypad.dc.html and
// AppKeypadDark.dc.html (side by side in test/goldens/compare/).
//
//   flutter test --update-goldens test/goldens
//
// Goldens are drawn on Windows; font rasterising differs slightly by OS, so a
// Linux CI run would regenerate rather than compare (tag `golden`).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final (name, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('shell on Keypad, $name, 390 x 844', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(await appUnderTest(theme: pref));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shell_keypad_$name.png'),
      );
    });

    testWidgets('tab bar, $name, as AppKeypad${name == 'dark' ? 'Dark' : ''}', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(await appUnderTest(theme: pref));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(VpTabBar),
        matchesGoldenFile('tab_bar_$name.png'),
      );
    });
  }
}
