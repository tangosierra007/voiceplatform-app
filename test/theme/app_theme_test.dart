import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/theme/app_theme.dart';

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    group(name, () {
      final s = theme.colorScheme;
      final vp = theme.extension<VpColors>()!;

      test('orange is a fill with ink text, never white', () {
        expect(s.primary, const Color(0xFFEA7500));
        expect(s.onPrimary, const Color(0xFF14110F));
        expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
        final filled = theme.filledButtonTheme.style!;
        expect(filled.backgroundColor!.resolve({}), const Color(0xFFEA7500));
        expect(filled.foregroundColor!.resolve({}), const Color(0xFF14110F));
        expect(
          theme.floatingActionButtonTheme.foregroundColor,
          const Color(0xFF14110F),
        );
      });

      test('orange as text is brand-text, readable on the surface', () {
        expect(
          vp.brandText,
          name == 'light' ? const Color(0xFFA85400) : const Color(0xFFFF8F1F),
        );
        expect(contrast(vp.brandText, vp.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(vp.brandText, vp.brandTint), greaterThanOrEqualTo(4.5));
        expect(
          theme.textButtonTheme.style!.foregroundColor!.resolve({}),
          vp.brandText,
        );
      });

      test('text and muted text pass 4.5:1 on canvas and surface', () {
        for (final bg in [vp.canvas, vp.surface]) {
          expect(contrast(vp.text, bg), greaterThanOrEqualTo(4.5));
          expect(contrast(vp.textMuted, bg), greaterThanOrEqualTo(4.5));
        }
      });

      test('fonts: Manrope body, Unbounded headlines', () {
        expect(theme.textTheme.bodyMedium!.fontFamily, 'Manrope');
        expect(theme.textTheme.headlineLarge!.fontFamily, 'Unbounded');
        expect(theme.textTheme.displayLarge!.fontVariations, [
          const FontVariation('wght', 800),
        ]);
      });
    });
  }

  test('dark follows the dark tokens', () {
    final d = AppTheme.dark();
    expect(d.brightness, Brightness.dark);
    expect(d.scaffoldBackgroundColor, const Color(0xFF0D0B0A));
    expect(d.colorScheme.surface, const Color(0xFF14110F));
    expect(AppTheme.light().scaffoldBackgroundColor, const Color(0xFFF5F2EE));
  });

  test('call screens: ink in both themes, answer green and hang up red with white icons', () {
    expect(
      AppTheme.callScreen().scaffoldBackgroundColor,
      const Color(0xFF14110F),
    );
    expect(VpCallColours.background, const Color(0xFF14110F));
    expect(VpCallColours.answer, const Color(0xFF2E7D32));
    expect(VpCallColours.hangUp, const Color(0xFFC62828));
    expect(VpCallColours.onControl, const Color(0xFFFFFFFF));
    expect(
      contrast(VpCallColours.onControl, VpCallColours.answer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(VpCallColours.onControl, VpCallColours.hangUp),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('tab bar badge colours from the artboard pass 4.5:1', () {
    for (final a in [vpLightArtboardColours, vpDarkArtboardColours]) {
      expect(a.badge, const Color(0xFFB42318));
      expect(contrast(a.onBadge, a.badge), greaterThanOrEqualTo(4.5));
    }
    expect(vpDarkArtboardColours.tabBar, const Color(0xFF1A1613));
    expect(vpLightArtboardColours.tabBar, vpLightColors.surface);
  });

  test('tab bar labels and icons pass 4.5:1 on the tab bar', () {
    for (final (c, a) in [
      (vpLightColors, vpLightArtboardColours),
      (vpDarkColors, vpDarkArtboardColours),
    ]) {
      expect(contrast(c.textMuted, a.tabBar), greaterThanOrEqualTo(4.5));
      expect(contrast(c.text, a.tabBar), greaterThanOrEqualTo(4.5));
      expect(contrast(c.brandText, c.brandTint), greaterThanOrEqualTo(4.5));
    }
  });
}
