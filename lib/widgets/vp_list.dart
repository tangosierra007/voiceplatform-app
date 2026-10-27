import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'vp_controls.dart';
import 'vp_icons.dart';

/// The page title on the tabs: `.ttl`, Unbounded 800 28/34.
class VpPageTitle extends StatelessWidget {
  const VpPageTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(text, style: vpTitle(context)),
        ),
      ),
      ?trailing,
    ],
  );
}

/// One `.seg` group: 32 px pills (48 px to touch), the pressed one ink with
/// light text in light mode and light with ink text in dark mode.
class VpSeg<T> extends StatelessWidget {
  const VpSeg({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// For screen readers: "Show", "Boxes".
  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      // One row that scrolls sideways when it doesn't fit (large text,
      // narrow phones), as a chip row does, rather than wrapping.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (v, text)) in options.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              _SegButton(
                text: text,
                pressed: v == value,
                onTap: () => onChanged(v),
                // Pressed: ink on light, grey-100 on dark (the artboards'
                // `[aria-pressed=true]`, dark override).
                pressedBg: dark ? c.grey100 : c.ink900,
                pressedFg: dark ? c.ink900 : c.grey100,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.text,
    required this.pressed,
    required this.onTap,
    required this.pressedBg,
    required this.pressedFg,
  });
  final String text;
  final bool pressed;
  final VoidCallback onTap;
  final Color pressedBg;
  final Color pressedFg;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      selected: pressed,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: VpTapPad(
        height: 32,
        onTap: onTap,
        child: Material(
          color: pressed ? pressedBg : c.surface,
          shape: StadiumBorder(
            side: BorderSide(color: pressed ? pressedBg : c.borderStrong),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              // 48 wide at least, so a short label like All is easy to hit.
              constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  text,
                  maxLines: 1,
                  style: VpType.body.copyWith(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: pressed ? pressedFg : c.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.row`: 12 px 20 px, a border under it.
class VpRow extends StatelessWidget {
  const VpRow({
    super.key,
    required this.children,
    this.onTap,
    this.semanticLabel,
    this.background,
  });
  final List<Widget> children;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(children: children),
    );
    return Material(
      color: background ?? Colors.transparent,
      child: onTap == null
          ? row
          : Semantics(
              button: true,
              label: semanticLabel,
              child: InkWell(onTap: onTap, child: row),
            ),
    );
  }
}

/// The 14 px row title and the 12 px muted line under it.
class VpRowText extends StatelessWidget {
  const VpRowText({
    super.key,
    required this.title,
    required this.subtitle,
    this.titleColour,
    this.titleWeight = FontWeight.w700,
  });
  final String title;
  final String? subtitle;
  final Color? titleColour;
  final FontWeight titleWeight;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: VpType.body.copyWith(
            fontSize: 15,
            fontWeight: titleWeight,
            fontVariations: [
              FontVariation('wght', titleWeight.value.toDouble()),
            ],
            color: titleColour ?? c.text,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VpType.caption.copyWith(
              color: c.textMuted,
              fontWeight: FontWeight.w500,
              fontVariations: const [FontVariation('wght', 500)],
            ),
          ),
      ],
    );
  }
}

/// A 38 px round outline button (Contacts' call button), 48 px to touch.
class VpRoundIconButton extends StatelessWidget {
  const VpRoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final VpIcon icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.borderStrong),
              ),
              child: Center(child: VpSvgIcon(icon, size: 18, colour: c.text)),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.vp-link`: brand text, underlined, 48 px to touch.
class VpLink extends StatelessWidget {
  const VpLink(this.text, {super.key, required this.onTap, this.size = 14});
  final String text;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              widthFactor: 1,
              child: Text(
                text,
                style: VpType.body.copyWith(
                  fontSize: size,
                  color: c.brandText,
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  decoration: TextDecoration.underline,
                  decorationColor: c.brandText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet line in the middle of an empty or failed list.
class VpEmpty extends StatelessWidget {
  const VpEmpty(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: vpMuted(context, size: 14, line: 20),
    ),
  );
}

/// The small-caps band ("22 COLLEAGUES · 4 FREE NOW").
class VpBand extends StatelessWidget {
  const VpBand(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Container(
      width: double.infinity,
      color: c.surfaceRaised,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Text(
        text.toUpperCase(),
        style: VpType.label.copyWith(
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 800)],
          color: c.textMuted,
        ),
      ),
    );
  }
}
