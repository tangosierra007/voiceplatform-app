// Goldens for the wide layout's shell. The rail at 884 x 1030 (2x) on
// Recents, compared with `nav.frail` in FoldRecents.dc.html (light; dark
// follows the dark tokens, there is no dark Fold artboard). And the shell
// either side of the switch: 599 dp (tab bar) and 600 dp (rail).
//
// The tab screens beside the rail are still the phone screens: list and
// detail, the phone-width keypad and the centred screens come in the next
// wide-layout PRs, which update the 600 dp golden.
//
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: artboardStatusBar * 2);
  tester.view.viewPadding = const FakeViewPadding(top: artboardStatusBar * 2);
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, String tab) async {
  final inRail = find.descendant(
    of: find.byType(VpNavRail),
    matching: find.text(tab),
  );
  await tester.tap(
    inRail.evaluate().isNotEmpty
        ? inRail
        : find.descendant(of: find.byType(VpTabBar), matching: find.text(tab)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  for (final (name, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('rail on Recents, $name, as FoldRecents', (tester) async {
      _window(tester, const Size(884, 1030));
      await tester.pumpWidget(await appUnderTest(theme: pref));
      await tester.pumpAndSettle();
      await _open(tester, 'Recents');
      await expectLater(
        find.byType(VpNavRail),
        matchesGoldenFile('rail_$name.png'),
      );
    });
  }

  for (final width in [599.0, 600.0]) {
    testWidgets('shell on Recents, light, ${width.toInt()} x 900', (
      tester,
    ) async {
      _window(tester, Size(width, 900));
      await tester.pumpWidget(await appUnderTest(theme: ThemePreference.light));
      await tester.pumpAndSettle();
      await _open(tester, 'Recents');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shell_recents_${width.toInt()}_light.png'),
      );
    });
  }
}
