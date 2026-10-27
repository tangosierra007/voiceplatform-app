// Screen reader labels, 48 px tap targets, 200 % text and the colour pairs
// on Recents, Voicemail, Greeting and Contacts. The presence dots always come
// with the status in words, so colour is never the only signal.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/shell/vp_tab_bar.dart';
import 'package:voiceplatform_app/theme/app_theme.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../support/app_harness.dart';
import '../support/phone.dart';

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(VpTabBar), matching: find.text(label));

final _now = DateTime.utc(2026, 10, 27, 0, 10);

Future<void> _open(
  WidgetTester tester,
  String screen, {
  ThemePreference theme = ThemePreference.light,
}) async {
  usePhone(tester);
  await tester.pumpWidget(
    await appUnderTest(
      clock: () => _now,
      theme: theme,
      phoneContacts: const [],
    ),
  );
  await _settle(tester);
  switch (screen) {
    case 'recents':
      await tester.tap(_tab('Recents'));
    case 'voicemail' || 'greeting':
      await tester.tap(_tab('Recents'));
      await _settle(tester);
      await tester.tap(find.text('Voicemail 2'));
      if (screen == 'greeting') {
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel('Greeting'));
      }
    case 'colleagues' || 'teams' || 'phone':
      await tester.tap(_tab('Contacts'));
      await _settle(tester);
      if (screen == 'teams') await tester.tap(find.text('Teams'));
      if (screen == 'phone') await tester.tap(find.text('Phone contacts'));
  }
  await _settle(tester);
}

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUpAll(loadAppFonts);

  for (final screen in [
    'recents',
    'voicemail',
    'greeting',
    'colleagues',
    'teams',
    'phone',
  ]) {
    testWidgets('$screen: labelled tap targets of 48 px', (tester) async {
      final h = tester.ensureSemantics();
      await _open(tester, screen);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      h.dispose();
    });

    testWidgets('$screen: 200 % text stays inside', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, screen);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'the colours these screens pair meet 4.5:1 (3:1 for large and icons)',
    () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final c = theme.extension<VpColors>()!;
        // Missed rows; muted captions on the canvas, the band and the card.
        expect(_contrast(c.statusBad, c.canvas), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textMuted, c.canvas), greaterThanOrEqualTo(4.5));
        expect(
          _contrast(c.textMuted, c.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(c.textMuted, c.surface), greaterThanOrEqualTo(4.5));
        // The Greeting link; the play icon on brand; the delete icon.
        expect(_contrast(c.brandText, c.canvas), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.onBrand, c.brand), greaterThanOrEqualTo(3));
        expect(_contrast(c.statusBad, c.surface), greaterThanOrEqualTo(3));
      }
    },
  );
}
