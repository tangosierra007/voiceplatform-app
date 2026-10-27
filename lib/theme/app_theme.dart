import 'package:flutter/material.dart';

import 'tokens.g.dart';

export 'tokens.g.dart';

/// Builds the light and dark [ThemeData] from the generated tokens.
///
/// Rules from the design system kept here:
/// - Orange (`brand`, #ea7500) is a fill with ink (`on-brand`) text and icons,
///   never white; orange as text uses `brand-text`.
/// - Call controls are the one place for green and red: [VpCallColours].
/// - In-call and incoming screens are ink in both themes: [AppTheme.callScreen].
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, vpLightColors);
  static ThemeData dark() => _build(Brightness.dark, vpDarkColors);

  /// The in-call and incoming screens: ink ground, light text, whatever the
  /// device theme is.
  static ThemeData callScreen() {
    final base = dark();
    return base.copyWith(
      scaffoldBackgroundColor: VpCallColours.background,
      canvasColor: VpCallColours.background,
      colorScheme: base.colorScheme.copyWith(surface: VpCallColours.background),
    );
  }

  static ThemeData _build(Brightness brightness, VpColors c) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandTint,
      onPrimaryContainer: c.text,
      secondary: c.brandText,
      onSecondary: dark ? c.ink900 : c.white,
      tertiary: c.statusInfo,
      onTertiary: dark ? c.ink900 : c.white,
      error: c.statusBad,
      onError: dark ? c.ink900 : c.white,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: c.ink900,
      scrim: c.ink900,
      inverseSurface: dark ? c.grey100 : c.charcoal800,
      onInverseSurface: dark ? c.ink900 : c.grey100,
      inversePrimary: c.brand,
    );

    TextStyle t(TextStyle s, Color colour) => s.copyWith(color: colour);
    final text = TextTheme(
      displayLarge: t(VpType.display, c.text),
      headlineLarge: t(VpType.h1, c.text),
      headlineMedium: t(VpType.h2, c.text),
      headlineSmall: t(VpType.stat, c.text),
      titleLarge: t(VpType.h3, c.text),
      titleMedium: t(VpType.bodyStrong, c.text),
      bodyLarge: t(VpType.bodyLg, c.text),
      bodyMedium: t(VpType.body, c.text),
      bodySmall: t(VpType.small, c.textMuted),
      labelLarge: t(VpType.button, c.text),
      labelMedium: t(VpType.label, c.textMuted),
      labelSmall: t(VpType.caption, c.textMuted),
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VpRadius.md),
    );
    const minSize = Size(64, VpSize.controlHeight);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      fontFamily: VpFonts.body,
      textTheme: text,
      focusColor: c.focus.withValues(alpha: 0.24),
      dividerColor: c.border,
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      extensions: [c],
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.onBrand,
              disabledBackgroundColor: c.surfaceRaised,
              disabledForegroundColor: c.textDisabled,
              textStyle: VpType.button,
              shape: buttonShape,
              minimumSize: minSize,
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                c.brandHover.withValues(alpha: 0.5),
              ),
            ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          textStyle: VpType.button,
          shape: buttonShape,
          minimumSize: minSize,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.borderStrong),
          textStyle: VpType.button,
          shape: buttonShape,
          minimumSize: minSize,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brandText,
          textStyle: VpType.button,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brand,
        foregroundColor: c.onBrand,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onBrand : c.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : c.borderStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.text,
        selectionColor: c.brandTint,
        selectionHandleColor: c.brand,
      ),
    );
  }
}

/// Call-control colours (tokens, by role). Green and red appear only here.
abstract final class VpCallColours {
  /// Ink ground of the in-call and incoming screens, in both themes.
  static const background = VpPalette.ink900;

  /// Answer: success-600 #2e7d32.
  static const answer = VpPalette.success600;

  /// Hang up and decline: danger-600 #c62828.
  static const hangUp = VpPalette.danger600;

  /// Icons on answer and hang up: white.
  static const onControl = VpPalette.white;

  /// Text on the call screens.
  static const text = VpPalette.grey100;
}

/// The tab bar's colours, by role, from tokens. The artboards draw the dark
/// bar #1a1613 and the badges #b42318; TJ (27 Oct) chose the nearest tokens.
abstract final class VpTabBarColours {
  /// Light: surface (white). Dark: charcoal-850 (#1f1b18), the nearest token
  /// to the artboard's #1a1613 and the dark theme's own navigation colour.
  static Color background(VpColors c, Brightness b) =>
      b == Brightness.dark ? c.charcoal850 : c.surface;

  /// danger-600 (#c62828) in both themes, the nearest token to #b42318.
  static const badge = VpPalette.danger600;

  /// White on danger-600: 5.6:1.
  static const onBadge = VpPalette.white;
}

extension VpThemeX on BuildContext {
  VpColors get vp => Theme.of(this).extension<VpColors>()!;
}
