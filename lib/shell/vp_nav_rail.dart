import 'dart:math' as math;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../calls/directory.dart';
import '../calls/me_state.dart';
import '../calls/numbers.dart';
import '../engine/engine_provider.dart';
import '../net/api.dart';
import '../screens/keypad/keypad_screen.dart';
import '../theme/app_theme.dart';
import 'tab_icons.dart';
import 'vp_tab_bar.dart';

/// The navigation rail of the wide layout (600 dp and wider), exactly as the
/// Fold artboards draw it (`nav.frail` in FoldRecents.dc.html and the other
/// Fold artboards): 80 px wide on the tab bar's background, a 1 px right
/// border, padding 12 0, items 6 px apart; each item 64 px wide with 4 px
/// above and below, a 56 x 32 pill holding a 22 px icon, a 4 px gap, then an
/// 11 px Manrope 700 label; the active pill brand-tint with a brand-text
/// icon and a text label; red count badges at top -2, right 4. Own status
/// at the bottom: a 36 px avatar with the presence dot.
///
/// Same tabs, badges and screen reader labels as [VpTabBar]; which tabs show
/// is decided in the shell state (`ShellStatus.tabs`), not here.
class VpNavRail extends StatelessWidget {
  const VpNavRail({
    super.key,
    required this.tabs,
    required this.current,
    required this.onSelect,
    this.badges = const {},
  });

  static const width = 80.0;

  final List<AppTab> tabs;
  final AppTab current;
  final ValueChanged<AppTab> onSelect;
  final Map<AppTab, int> badges;

  /// One text size for every label (task 489): the user's text size, made
  /// smaller only as far as the widest visible label needs to fit the 64 px
  /// column. Before, each label shrank on its own, so at 200 % a short
  /// label ("Me") drew larger than the long ones.
  static TextScaler labelScaler(BuildContext context, List<AppTab> tabs) {
    final scaler = MediaQuery.textScalerOf(context);
    // As the Text draws it: the ambient style (letter spacing and the like)
    // under the label's own.
    final style = DefaultTextStyle.of(context).style
        .merge(_RailItem.labelStyle);
    double widestAt(TextScaler s) {
      var widest = 0.0;
      for (final t in tabs) {
        final p = TextPainter(
          text: TextSpan(text: t.label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: s,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, p.width);
        p.dispose();
      }
      return widest;
    }

    // The labels share one font size, so a linear scaler draws them exactly.
    final base = _RailItem.labelStyle.fontSize!;
    var fitted = TextScaler.linear(scaler.scale(base) / base);
    // Text width is not quite proportional to its size (glyph advances are
    // rounded), so measure again until the widest label fits.
    for (var i = 0; i < 4; i++) {
      final widest = widestAt(fitted);
      if (widest <= _RailItem.width) break;
      final size = fitted.scale(base) * _RailItem.width / widest * 0.999;
      fitted = TextScaler.linear(size / base);
    }
    return fitted;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final insets = MediaQuery.paddingOf(context);
    final labels = labelScaler(context, tabs);
    // As the Fold artboards: the status bar runs across the whole width on
    // the canvas, and the rail starts below it.
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(top: insets.top),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'App',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: VpTabBarColours.background(
                c,
                Theme.of(context).brightness,
              ),
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: SizedBox(
              // The left inset (a cut-out in landscape) widens the rail; the
              // items keep their 80 px column.
              width: width + insets.left,
              child: Padding(
                padding: EdgeInsets.only(left: insets.left),
                // Short windows (a phone in landscape over 600 dp) or large
                // text: the rail scrolls rather than overflowing.
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            12,
                            0,
                            12 + insets.bottom,
                          ),
                          child: Column(
                            children: [
                              for (final (i, t) in tabs.indexed) ...[
                                if (i > 0) const SizedBox(height: 6),
                                _RailItem(
                                  tab: t,
                                  active: t == current,
                                  badge: badges[t] ?? 0,
                                  labelScaler: labels,
                                  onTap: () => onSelect(t),
                                ),
                              ],
                              const Spacer(),
                              const SizedBox(height: 6),
                              const OwnStatus(),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tab,
    required this.active,
    required this.badge,
    required this.labelScaler,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final int badge;
  final TextScaler labelScaler;
  final VoidCallback onTap;

  /// The item's column.
  static const width = 64.0;

  /// The badge's left edge at 100 %: right 4 with the 18 px badge, as the
  /// artboards draw it, on the 22 px icon's top right corner (the icon runs
  /// from 21 to 43). A badge grown by large text keeps this left edge and
  /// grows to the right, so it never covers more of the icon (task 489).
  static const badgeLeft = width - 4 - 18;

  static const labelStyle = TextStyle(
    fontFamily: VpFonts.body,
    fontSize: 11,
    height: 1,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: tabSemanticLabel(tab, badge),
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? c.brandTint : null,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: SvgPicture.string(
                        tab.svg,
                        width: 22,
                        height: 22,
                        theme: SvgTheme(
                          currentColor: active ? c.brandText : c.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // The rail's one label size (VpNavRail.labelScaler): it
                    // grows with the text size and the widest label fits
                    // the 64 px column, so 200 % never runs past the item.
                    // The FittedBox only guards against a font that
                    // measures differently.
                    SizedBox(
                      width: width,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          softWrap: false,
                          textScaler: labelScaler,
                          style: labelStyle.copyWith(
                            color: active ? c.text : c.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  left: 0,
                  // Up to the rail's right border: the item is centred in
                  // the 80 px rail, 8 px either side.
                  right: -((VpNavRail.width - width) / 2 - 1),
                  height: _badgeBox,
                  child: CustomSingleChildLayout(
                    delegate: const _BadgeLayout(),
                    child: VpCountBadge(count: badge),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The box the count badge is laid out in: tall enough for the badge at
/// its 1.5x text size limit (27 px).
const _badgeBox = 28.0;

/// Puts the count badge at [_RailItem.badgeLeft], or further left only when
/// a wide count ("99+" at large text) would otherwise pass the rail's
/// border. The badge sizes itself, as it does in the tab bar.
class _BadgeLayout extends SingleChildLayoutDelegate {
  const _BadgeLayout();

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    math.max(0, math.min(_RailItem.badgeLeft, size.width - childSize.width)),
    0,
  );

  @override
  bool shouldRelayout(_BadgeLayout oldDelegate) => false;
}

/// My own status at the foot of the rail: my initials with the presence
/// dot (green free, orange on a call, red do not disturb, grey away or
/// offline). Tapping it opens the status sheet, as the keypad's chip does.
class OwnStatus extends ConsumerWidget {
  const OwnStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final me = ref.watch(meProvider).value;
    final offline = ref.watch(offlineProvider);
    final status = ref.watch(myStatusProvider) ?? StatusStatus.available;
    final onCall = (ref.watch(activeCallsProvider).value ?? const []).any(
      (x) => x.state != CallState.incoming && x.state != CallState.ended,
    );
    final (look, label) = offline
        ? (PresenceLook.away, 'Offline')
        : switch (status) {
            StatusStatus.dnd => (PresenceLook.dnd, 'Do not disturb'),
            StatusStatus.away => (PresenceLook.away, 'Away'),
            _ when onCall => (PresenceLook.onCall, 'On a call'),
            _ => (PresenceLook.free, 'Available'),
          };
    final dot = switch (look) {
      PresenceLook.free => c.statusOk,
      PresenceLook.onCall => c.brand,
      PresenceLook.dnd => c.statusBad,
      PresenceLook.away => c.borderStrong,
    };
    final initials = me == null ? '' : (me.initials ?? initialsOf(me.name));
    return Semantics(
      container: true,
      button: !offline,
      label: offline ? 'Your status: $label' : 'Your status: $label. Change',
      onTap: offline ? null : () => showStatusSheet(context, ref, status),
      excludeSemantics: true,
      child: InkResponse(
        onTap: offline ? null : () => showStatusSheet(context, ref, status),
        radius: 28,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      shape: BoxShape.circle,
                    ),
                    child: initials.isEmpty
                        ? SvgPicture.string(
                            meIconSvg,
                            width: 18,
                            height: 18,
                            theme: SvgTheme(currentColor: c.textMuted),
                          )
                        : Text(
                            initials,
                            textScaler: TextScaler.noScaling,
                            style: VpType.body.copyWith(
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              fontVariations: const [
                                FontVariation('wght', 800),
                              ],
                              color: c.text,
                            ),
                          ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.canvas, width: 2),
                      ),
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
