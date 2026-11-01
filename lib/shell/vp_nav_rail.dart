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

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final insets = MediaQuery.paddingOf(context);
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
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  static const _labelStyle = TextStyle(
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
          width: 64,
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
                    // Grows with the text size and shrinks to fit the 64 px
                    // column, so 200 % never runs past the item.
                    SizedBox(
                      width: 64,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          softWrap: false,
                          style: _labelStyle.copyWith(
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
                  right: 4,
                  child: VpCountBadge(count: badge),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
