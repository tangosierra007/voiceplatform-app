import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'tab_icons.dart';

/// The five app tabs, in the artboards' order.
enum AppTab {
  keypad('Keypad', keypadIconSvg),
  recents('Recents', recentsIconSvg),
  contacts('Contacts', contactsIconSvg),
  messages('Messages', messagesIconSvg),
  me('Me', meIconSvg);

  const AppTab(this.label, this.svg);
  final String label;
  final String svg;
}

/// The tab bar exactly as the artboards draw it (`nav.tabs` in
/// AppKeypad.dc.html and AppKeypadDark.dc.html):
/// padding 8 6 26, a 1 px top border, items spaced around; each item a
/// 52 x 30 pill holding a 22 px icon, a 3 px gap, then an 11 px Manrope 700
/// label; the active pill brand-tint with a brand-text icon and a text label;
/// red count badges 18 px high at top -2, right 6.
class VpTabBar extends StatelessWidget {
  const VpTabBar({
    super.key,
    required this.tabs,
    required this.current,
    required this.onSelect,
    this.badges = const {},
  });

  /// Visible tabs; Messages is left out when the user has no SMS line.
  final List<AppTab> tabs;
  final AppTab current;
  final ValueChanged<AppTab> onSelect;
  final Map<AppTab, int> badges;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // Its own layer: badge changes repaint only the bar, and goldens can
    // capture it alone.
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.vpArtboard.tabBar,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Padding(
          // 8 px below the 1 px top border (a BoxDecoration border takes no space).
          padding: EdgeInsets.fromLTRB(6, 1 + 8, 6, math.max(26, bottomInset)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in tabs)
                Expanded(
                  child: _TabItem(
                    tab: t,
                    active: t == current,
                    badge: badges[t] ?? 0,
                    onTap: () => onSelect(t),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  static const _labelStyle = TextStyle(
    fontFamily: VpFonts.body,
    fontSize: 11,
    // The artboards inherit .vp-root's 22 px line height here.
    height: 22 / 11,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );

  String get _semanticLabel {
    if (badge <= 0) return tab.label;
    return switch (tab) {
      AppTab.messages => '${tab.label}, $badge unread',
      _ => '${tab.label}, $badge new',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final a = context.vpArtboard;
    final iconColour = active ? c.brandText : c.textMuted;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.brandTint : null,
              borderRadius: BorderRadius.circular(99),
            ),
            child: SvgPicture.string(
              tab.svg,
              width: 22,
              height: 22,
              theme: SvgTheme(currentColor: iconColour),
            ),
          ),
          const SizedBox(height: 3),
          // Grows with the text size and shrinks to fit the slot, so 200 %
          // never runs past the tab.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              tab.label,
              maxLines: 1,
              softWrap: false,
              style: _labelStyle.copyWith(color: active ? c.text : c.textMuted),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: _semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        radius: 40,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              content,
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: 6,
                  child: _Badge(
                    count: badge,
                    colour: a.badge,
                    textColour: a.onBadge,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.colour,
    required this.textColour,
  });

  final int count;
  final Color colour;
  final Color textColour;

  @override
  Widget build(BuildContext context) {
    // The count is in the tab's screen reader label; the badge itself grows
    // to 1.5x at most so it stays on the icon.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: VpFonts.body,
            fontSize: 11,
            height: 18 / 11,
            leadingDistribution: TextLeadingDistribution.even,
            fontWeight: FontWeight.w800,
            fontVariations: const [FontVariation('wght', 800)],
            color: textColour,
          ),
        ),
      ),
    );
  }
}
