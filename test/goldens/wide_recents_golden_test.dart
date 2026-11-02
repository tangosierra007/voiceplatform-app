// FoldRecents at 884 x 1030 (2x): the calls, and Westgate Supplies (the
// newest, as on the artboard) beside them with Call back, the caller ID,
// the voicemail and the recent calls; light and dark (dark follows the dark
// tokens; there is no dark Fold artboard), at 3:40 pm on Tuesday 27 October
// in Melbourne. Also the proof widths: 690 (Galaxy Z Fold5 portrait), 680 at
// 200% text (the narrowest split), 679 (the list beside the rail), 744 and
// 852.
//
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/shell/vp_nav_rail.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 4, 40);

void main() {
  setUpAll(loadAppFonts);

  for (final (name, pref, size, text) in [
    ('light', ThemePreference.light, const Size(884, 1030), 1.0),
    ('dark', ThemePreference.dark, const Size(884, 1030), 1.0),
    // A Galaxy Z Fold5 unfolded in portrait.
    ('690_light', ThemePreference.light, const Size(690, 1030), 1.0),
    ('690_dark', ThemePreference.dark, const Size(690, 1030), 1.0),
    // The narrowest split, at 200% text.
    ('680_200pct_light', ThemePreference.light, const Size(680, 1030), 2.0),
    ('680_200pct_dark', ThemePreference.dark, const Size(680, 1030), 2.0),
    // One under: the phone's list beside the rail.
    ('679_light', ThemePreference.light, const Size(679, 1030), 1.0),
    ('744_light', ThemePreference.light, const Size(744, 1030), 1.0),
    ('852_light', ThemePreference.light, const Size(852, 1030), 1.0),
  ]) {
    testWidgets('FoldRecents, $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
            for (final v in fx.voicemails)
              'POST /voicemail/messages/${v['id']}/media-url': (_) => {
                'url': '/app/v1/media/token-${v['id']}',
                'expiresAt': '2026-10-27T00:15:00.000Z',
              },
          }),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(VpNavRail),
          matching: find.text('Recents'),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('recents_wide_$name.png'),
      );
    });
  }
}
