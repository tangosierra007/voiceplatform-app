import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'vp_controls.dart';

/// The list pane's head on the Fold artboards: padding 10 16 12, a 24/30
/// Unbounded 800 title, then the filters, 12 px apart.
class WideListHeader extends StatelessWidget {
  const WideListHeader({
    super.key,
    required this.title,
    this.trailing,
    this.children = const [],
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: vpTitle(context, size: 24, line: 30)),
              ),
            ),
            ?trailing,
          ],
        ),
        for (final w in children) ...[const SizedBox(height: 12), w],
      ],
    ),
  );
}

/// `.lrow`: padding 11 16, 12 px gaps, a 1 px bottom border; the selected
/// row on the brand tint (`aria-selected`).
class WideListRow extends StatelessWidget {
  const WideListRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
    required this.children,
  });

  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.brandTint : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(children: _gapped(children)),
          ),
        ),
      ),
    );
  }

  static List<Widget> _gapped(List<Widget> ws) => [
    for (final (i, w) in ws.indexed) ...[
      if (i > 0) const SizedBox(width: 12),
      w,
    ],
  ];
}

/// `.vp-pill.vp-pill--off` at the list's 10 px, 18 px high: a hollow dot and
/// the line's name ("Sales mobile").
class VpOffPill extends StatelessWidget {
  const VpOffPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.textMuted, width: 2),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.5),
              style: VpType.caption.copyWith(
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                color: c.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
