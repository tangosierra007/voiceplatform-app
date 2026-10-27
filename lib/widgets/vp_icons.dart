import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons copied unchanged from the artboards' inline SVGs (24 px viewBox,
/// stroke `currentColor`, drawn with the colour given).
enum VpIcon {
  /// AppSignIn "Scan the QR code instead".
  qr(
    '<rect x="3.5" y="3.5" width="6.5" height="6.5" rx="1"/><rect x="14" y="3.5" width="6.5" height="6.5" rx="1"/><rect x="3.5" y="14" width="6.5" height="6.5" rx="1"/><path d="M14 14h2.5v2.5H14zM18 18h2.5v2.5H18zM14 18.5h1.5M18.5 14h2"/>',
  ),

  /// AppCode back.
  back('<path d="M15 5l-7 7 7 7"/>'),

  /// AppCode envelope.
  mail(
    '<rect x="3.5" y="5.5" width="17" height="13" rx="2"/><path d="M4 7l8 6 8-6"/>',
  ),

  /// AppCode note, AppBasic tile.
  lock(
    '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
  ),

  /// AppBasic list ticks.
  check('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),

  /// AppUpdate tile.
  update('<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 5v6h-6"/>'),

  /// AppEmergency tile.
  siren(
    '<path d="M7 18v-6a5 5 0 0 1 10 0v6"/><path d="M5 21h14M12 3v2M4.5 6l1.4 1.4M19.5 6l-1.4 1.4"/>',
  ),

  /// AppEmergency "Call 000 now", the keypad call button.
  phone(
    '<path d="M6.6 3.5h2.3c.4 0 .8.3.9.7l1 3.3c.1.4 0 .8-.3 1.1l-1.4 1.3a12 12 0 0 0 5 5l1.3-1.4c.3-.3.7-.4 1.1-.3l3.3 1c.4.1.7.5.7.9v2.3c0 1.1-.9 2-2 2A17.5 17.5 0 0 1 4.6 5.5c0-1.1.9-2 2-2z"/>',
  );

  const VpIcon(this.body);
  final String body;
}

class VpSvgIcon extends StatelessWidget {
  const VpSvgIcon(
    this.icon, {
    super.key,
    required this.size,
    required this.colour,
    this.strokeWidth = 2,
  });

  final VpIcon icon;
  final double size;
  final Color colour;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final svg =
        '<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">${icon.body}</svg>';
    return ExcludeSemantics(
      child: SvgPicture.string(
        svg,
        width: size,
        height: size,
        theme: SvgTheme(currentColor: colour),
      ),
    );
  }
}
