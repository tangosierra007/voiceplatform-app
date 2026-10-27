import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'vp_icons.dart';

/// The artboards' `.ttl` title: Unbounded 800, 28/34, -0.02em.
TextStyle vpTitle(BuildContext context, {double size = 28, double line = 34}) =>
    TextStyle(
      fontFamily: VpFonts.headline,
      fontSize: size,
      height: line / size,
      leadingDistribution: TextLeadingDistribution.even,
      fontWeight: FontWeight.w800,
      fontVariations: const [FontVariation('wght', 800)],
      letterSpacing: -0.02 * size,
      color: context.vp.text,
    );

/// `.muted` body copy, 15/22 unless given.
TextStyle vpMuted(BuildContext context, {double size = 15, double line = 22}) =>
    VpType.body.copyWith(
      fontSize: size,
      height: line / size,
      color: context.vp.textMuted,
    );

/// The bottom space the artboards keep for the home indicator (34 px), or
/// the phone's own inset when larger.
double vpBottomInset(BuildContext context) =>
    math.max(34, MediaQuery.viewPaddingOf(context).bottom);

enum VpButtonKind { primary, outline, ghost }

/// `.vp-btn`: Unbounded 700, 8 px radius, 2 px border. `--lg` is 15 px text;
/// the artboards set 54 px height on the large ones.
class VpButton extends StatelessWidget {
  const VpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = VpButtonKind.primary,
    this.icon,
    this.height = 54,
    this.large = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final VpButtonKind kind;
  final VpIcon? icon;
  final double height;
  final bool large;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (kind) {
      _ when !enabled && kind == VpButtonKind.primary => (
        c.surfaceRaised,
        c.textDisabled,
        c.border,
      ),
      VpButtonKind.primary => (c.brand, c.onBrand, c.brand),
      VpButtonKind.outline => (c.surface, c.text, c.borderStrong),
      VpButtonKind.ghost => (Colors.transparent, c.text, Colors.transparent),
    };
    final text = TextStyle(
      fontFamily: VpFonts.headline,
      fontSize: large ? 15 : 14,
      height: 20 / (large ? 15 : 14),
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
      letterSpacing: -0.005 * (large ? 15 : 14),
      color: fg,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VpRadius.md),
          side: BorderSide(color: border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          overlayColor: WidgetStatePropertyAll(
            kind == VpButtonKind.primary
                ? c.brandHover.withValues(alpha: 0.4)
                : c.surfaceRaised,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: large ? VpSpace.s5 : VpSpace.s4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  else if (icon != null)
                    VpSvgIcon(icon!, size: 20, colour: fg),
                  if (busy || icon != null) const SizedBox(width: VpSpace.s2),
                  Flexible(
                    child: Text(
                      label,
                      style: text,
                      textAlign: TextAlign.center,
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded tile holding an icon (AppCode, AppBasic, AppUpdate, AppEmergency).
class VpIconTile extends StatelessWidget {
  const VpIconTile({
    super.key,
    required this.icon,
    required this.size,
    required this.radius,
    required this.iconSize,
    required this.background,
    required this.colour,
    this.border,
  });

  final VpIcon icon;
  final double size;
  final double radius;
  final double iconSize;
  final Color background;
  final Color colour;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      border: border == null ? null : Border.all(color: border!),
    ),
    child: VpSvgIcon(icon, size: iconSize, colour: colour),
  );
}

/// The logo: five ink bars tracing a V on an orange tile, then the wordmark
/// "Voice" (Unbounded 800) "Platform" (500), as AppSignIn draws it.
class VpLogo extends StatelessWidget {
  const VpLogo({super.key});

  @override
  Widget build(BuildContext context) {
    const bars = [
      (6.0, -7.0),
      (10.0, -3.0),
      (14.0, 2.0),
      (10.0, -3.0),
      (6.0, -7.0),
    ];
    final word = TextStyle(
      fontFamily: VpFonts.headline,
      fontSize: 18,
      height: 1,
      fontWeight: FontWeight.w800,
      fontVariations: const [FontVariation('wght', 800)],
      color: context.vp.text,
    );
    return Semantics(
      label: 'VoicePlatform',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: VpPalette.orange500,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (i, (h, top)) in bars.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Transform.translate(
                    offset: Offset(0, top / 2),
                    child: Container(
                      width: 3,
                      height: h,
                      decoration: BoxDecoration(
                        color: VpPalette.ink900,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text.rich(
            TextSpan(
              text: 'Voice',
              children: [
                TextSpan(
                  text: 'Platform',
                  style: word.copyWith(
                    fontWeight: FontWeight.w500,
                    fontVariations: const [FontVariation('wght', 500)],
                  ),
                ),
              ],
            ),
            style: word,
            // A brand mark: its size is fixed; the label carries the name.
            textScaler: TextScaler.noScaling,
          ),
        ],
      ),
    );
  }
}
