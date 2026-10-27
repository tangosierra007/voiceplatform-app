// Goldens for Recents, Voicemail and Contacts at 390 x 844 (2x), set up as
// AppRecents (light and dark), AppVoicemail and AppContacts show them, on
// the canvas sample data at 11:10 am on Tuesday 27 October in Melbourne.
// Side by side with the artboards in test/goldens/compare/.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/features/recents/media_player.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import '../support/app_harness.dart';
import '../support/phone.dart';

final _now = DateTime.utc(2026, 10, 27, 0, 10);

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

Future<void> _shot(WidgetTester t, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile(name));

void main() {
  setUpAll(loadAppFonts);

  for (final (mode, pref) in [
    ('light', ThemePreference.light),
    ('dark', ThemePreference.dark),
  ]) {
    testWidgets('AppRecents $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(theme: pref, clock: () => _now),
      );
      await _settle(tester);
      await tester.tap(_tab('Recents'));
      await _settle(tester);
      await _shot(tester, 'recents_$mode.png');
    });

    testWidgets('AppVoicemail $mode', (tester) async {
      usePhone(tester);
      final player = FakeMediaPlayer();
      final api = FakeApi({
        'POST /voicemail/messages/${fx.voicemails.first['id']}/media-url': (
          _,
        ) => {'url': '/app/v1/media/t', 'expiresAt': '2026-10-27T00:15:00Z'},
      });
      await tester.pumpWidget(
        await appUnderTest(
          theme: pref,
          clock: () => _now,
          player: player,
          api: api,
        ),
      );
      await _settle(tester);
      await tester.tap(_tab('Recents'));
      await _settle(tester);
      await tester.tap(find.text('Voicemail 2'));
      await _settle(tester);
      // Playing, 30 s in, as the artboard.
      await tester.tap(find.bySemanticsLabel('Play'));
      await _settle(tester);
      player.emit(
        const PlaybackState(
          playing: true,
          position: Duration(seconds: 30),
          duration: Duration(seconds: 75),
        ),
      );
      await _settle(tester);
      await _shot(tester, 'voicemail_$mode.png');
    });

    testWidgets('AppContacts $mode', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        await appUnderTest(theme: pref, clock: () => _now),
      );
      await _settle(tester);
      await tester.tap(_tab('Contacts'));
      await _settle(tester);
      await _shot(tester, 'contacts_$mode.png');
    });
  }

  testWidgets('Greeting light', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      await appUnderTest(theme: ThemePreference.light, clock: () => _now),
    );
    await _settle(tester);
    await tester.tap(_tab('Recents'));
    await _settle(tester);
    await tester.tap(find.text('Voicemail 2'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Greeting'));
    await _settle(tester);
    await _shot(tester, 'greeting_light.png');
  });

  // The A53 as WS6 tested it: 384 dp wide, default font scale 1.1.
  for (final screen in ['recents', 'voicemail']) {
    testWidgets('$screen at 384 dp and 110 %', (tester) async {
      usePhone(tester);
      tester.view.physicalSize = const Size(384 * 2, 854 * 2);
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final player = FakeMediaPlayer();
      await tester.pumpWidget(
        await appUnderTest(
          theme: ThemePreference.light,
          clock: () => _now,
          player: player,
        ),
      );
      await _settle(tester);
      await tester.tap(_tab('Recents'));
      await _settle(tester);
      if (screen == 'voicemail') {
        await tester.tap(find.text('Voicemail 2'));
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
      await _shot(tester, '${screen}_384_110.png');
    });
  }
}