import 'dart:async';
import 'dart:math' as math;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calls/numbers.dart';
import '../../auth/auth.dart';
import '../../engine/engine_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_icons.dart';

/// Body copy on the ink call screens.
TextStyle callText(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? colour,
  double? height,
}) => TextStyle(
  fontFamily: VpFonts.body,
  fontSize: size,
  height: height,
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: colour ?? VpCallColours.text,
);

/// The caller's name: Unbounded 800 28/34, -0.02em.
const callName = TextStyle(
  fontFamily: VpFonts.headline,
  fontSize: 28,
  height: 34 / 28,
  leadingDistribution: TextLeadingDistribution.even,
  fontWeight: FontWeight.w800,
  fontVariations: [FontVariation('wght', 800)],
  letterSpacing: -0.56,
  color: VpCallColours.text,
);

/// The small caps line at the top: "INCOMING · SALES GROUP".
TextStyle callEyebrow() => callText(
  13,
  weight: FontWeight.w700,
  colour: VpCallColours.muted,
).copyWith(letterSpacing: 0.78);

/// The ink ground for incoming, in call and transfer, in both themes.
class CallScaffold extends StatelessWidget {
  const CallScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.callScreen(),
    child: Scaffold(
      backgroundColor: VpCallColours.background,
      body: SafeArea(bottom: false, child: child),
    ),
  );
}

/// The round avatar with initials (or a phone glyph for a bare number).
class CallAvatar extends StatelessWidget {
  const CallAvatar({
    super.key,
    required this.name,
    required this.size,
    this.rings = false,
  });
  final String? name;
  final double size;

  /// The incoming screen's two brand rings (14 px and 30 px).
  final bool rings;

  @override
  Widget build(BuildContext context) {
    final initials = name == null ? '' : initialsOf(name!);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VpCallColours.avatar,
        shape: BoxShape.circle,
        boxShadow: rings
            ? [
                BoxShadow(color: VpCallColours.ringInner, spreadRadius: 14),
                BoxShadow(color: VpCallColours.ringOuter, spreadRadius: 30),
              ]
            : null,
      ),
      child: initials.isEmpty
          ? VpSvgIcon(
              VpIcon.phone,
              size: size * 0.36,
              colour: VpCallColours.text,
            )
          : Text(
              initials,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: VpFonts.headline,
                fontSize: size * 0.34,
                height: 1,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                color: VpCallColours.text,
              ),
            ),
    );
  }
}

/// A 68 px round call control with its label under it (`.cbtn`).
class CallControl extends StatelessWidget {
  const CallControl({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.on = false,
    this.background,
    this.iconColour,
    this.size = 68,
    this.iconSize = 26,
    this.rotate = false,
    this.semanticLabel,
  });

  final String label;
  final VpIcon icon;
  final VoidCallback? onPressed;

  /// A toggle that is on (Mute, Speaker, Hold): grey-100 with an ink icon.
  final bool on;
  final Color? background;
  final Color? iconColour;
  final double size;
  final double iconSize;

  /// The hang-up handset, turned 135 degrees.
  final bool rotate;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bg =
        background ?? (on ? VpCallColours.controlOn : VpCallColours.control);
    final fg =
        iconColour ?? (on ? VpCallColours.onControlOn : VpCallColours.text);
    Widget glyph = VpSvgIcon(
      icon,
      size: iconSize,
      colour: fg,
      strokeWidth: rotate || icon == VpIcon.phone ? 2.2 : 2,
    );
    if (rotate) {
      glyph = Transform.rotate(angle: 135 * math.pi / 180, child: glyph);
    }
    return Semantics(
      button: true,
      toggled:
          onPressed != null &&
              (label == 'Mute' || label == 'Speaker' || label == 'Hold')
          ? on
          : null,
      enabled: onPressed != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: bg,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(child: glyph),
                ),
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 8),
              // At most 96 px wide: larger text shrinks to fit, never overflows.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: math.max(size, 96)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    // 12 px on the artboard's inherited 22 px line.
                    style: callText(
                      12,
                      weight: FontWeight.w600,
                      height: 22 / 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ENCRYPTED, HD: mono 700 11 px in a 4 px-radius outline.
class CallTag extends StatelessWidget {
  const CallTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: VpCallColours.tagBorder),
      borderRadius: BorderRadius.circular(VpRadius.sm),
    ),
    child: Text(
      text,
      // The artboard sets these in the mono family; JetBrains Mono is not
      // bundled and phones have no common monospace, so Manrope 700 (the body
      // font) draws them the same size everywhere.
      style: VpType.mono.copyWith(
        fontFamily: VpFonts.body,
        fontFamilyFallback: const <String>[],
        letterSpacing: 0.4,
        fontSize: 11,
        height: 1,
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
        color: VpCallColours.soft,
      ),
    ),
  );
}

/// The call timer from [since], ticking each second (`01:24`).
class CallTimer extends StatefulWidget {
  const CallTimer({super.key, required this.since, this.style, this.clock});
  final DateTime since;
  final TextStyle? style;

  /// Defaults to the app's clock (clockProvider).
  final DateTime Function()? clock;

  @override
  State<CallTimer> createState() => _CallTimerState();
}

class _CallTimerState extends State<CallTimer> {
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  DateTime _now() {
    final own = widget.clock;
    if (own != null) return own();
    final DateTime Function() app = ProviderScope.containerOf(context)
        .read(clockProvider);
    return app();
  }

  @override
  Widget build(BuildContext context) => Text(
    callTimer(_now().difference(widget.since)),
    style:
        widget.style ??
        callText(
          18,
          weight: FontWeight.w700,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  );
}

/// The live waveform: ten 4 px bars, orange-400, their heights following the
/// engine's input level (about 20 Hz). Grey when muted.
class LiveWaveform extends ConsumerStatefulWidget {
  const LiveWaveform({super.key, required this.muted});
  final bool muted;

  /// The artboard's resting heights.
  static const heights = [10.0, 18, 28, 16, 24, 12, 20, 14, 26, 10];

  @override
  ConsumerState<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends ConsumerState<LiveWaveform> {
  StreamSubscription<double>? _sub;
  final _levels = List<double>.filled(10, 0.6, growable: true);

  @override
  void initState() {
    super.initState();
    _sub = ref.read(callEngineProvider).inputLevel.listen((l) {
      if (!mounted) return;
      setState(() {
        _levels.removeAt(0);
        _levels.add(l);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = widget.muted ? VpCallColours.tagBorder : VpCallColours.wave;
    return ExcludeSemantics(
      child: SizedBox(
        height: 30,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 10; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Container(
                width: 4,
                height:
                    LiveWaveform.heights[i] *
                    (widget.muted
                        ? 0.45
                        : 0.45 + 0.55 * _levels[i].clamp(0, 1)),
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The name to show for a call: the engine's, a match on this phone, or the
/// number itself.
String callTitle(CallSnapshot c, String? localName) =>
    c.remoteName ?? localName ?? formatAuNumber(c.remoteNumber);

/// The number under the name, or null when the title already is the number.
String? callSubtitle(CallSnapshot c, String? localName) =>
    c.remoteName == null && localName == null
    ? null
    : formatAuNumber(c.remoteNumber);
