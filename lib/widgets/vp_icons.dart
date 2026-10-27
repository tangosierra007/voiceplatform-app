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

  /// AppIncoming "To voicemail".
  voicemail(
    '<circle cx="6.5" cy="12" r="3.5"/><circle cx="17.5" cy="12" r="3.5"/><path d="M6.5 15.5h11"/>',
  ),

  /// AppInCall Mute, AppMicrophone tile.
  micOff(
    '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 11 4.7M18.5 11v0"/><path d="M12 17.5V21"/><path d="M4 4l16 16"/>',
  ),

  /// AppInCall Keypad (also the tab bar's).
  keypad(
    '<circle cx="6" cy="6" r="1.4"/><circle cx="12" cy="6" r="1.4"/><circle cx="18" cy="6" r="1.4"/><circle cx="6" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18" cy="12" r="1.4"/><circle cx="6" cy="18" r="1.4"/><circle cx="12" cy="18" r="1.4"/><circle cx="18" cy="18" r="1.4"/>',
  ),

  /// AppInCall Speaker.
  speaker(
    '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
  ),

  /// AppInCall Hold.
  hold('<path d="M9 5.5v13M15 5.5v13"/>'),

  /// AppInCall Transfer.
  transfer(
    '<path d="M4 8h13M13.5 4.5L17 8l-3.5 3.5"/><path d="M20 16H7M10.5 12.5L7 16l3.5 3.5"/>',
  ),

  /// AppInCall Add call.
  plus('<path d="M12 5v14M5 12h14"/>'),

  /// AppKeypad delete.
  backspace(
    '<path d="M8.5 5.5H20v13H8.5L3.5 12z"/><path d="M11.5 9.5l5 5M16.5 9.5l-5 5"/>',
  ),

  /// AppKeypad caller ID chip.
  chevronDown('<path d="M6 9.5l6 6 6-6"/>'),

  /// AppTransfer search.
  search('<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/>'),

  /// AppOffline banner.
  wifiOff(
    '<path d="M3 3l18 18"/><path d="M8.5 16.5a5 5 0 0 1 7 0M5 12.5a10 10 0 0 1 4.5-2.4M14.5 10.1A10 10 0 0 1 19 12.5M2 8.8a15 15 0 0 1 4.3-2.5M11 5a15 15 0 0 1 11 3.8"/><circle cx="12" cy="20" r=".8"/>',
  ),

  /// AppRecents: missed, incoming, outgoing.
  missedCall(
    '<path d="M6.6 3.5h2.3c.4 0 .8.3.9.7l1 3.3c.1.4 0 .8-.3 1.1l-1.4 1.3a12 12 0 0 0 5 5l1.3-1.4c.3-.3.7-.4 1.1-.3l3.3 1c.4.1.7.5.7.9v2.3c0 1.1-.9 2-2 2A17.5 17.5 0 0 1 4.6 5.5c0-1.1.9-2 2-2z"/><path d="M15 4l5 5M20 4l-5 5"/>',
  ),
  incomingCall(
    '<path d="M6.6 3.5h2.3c.4 0 .8.3.9.7l1 3.3c.1.4 0 .8-.3 1.1l-1.4 1.3a12 12 0 0 0 5 5l1.3-1.4c.3-.3.7-.4 1.1-.3l3.3 1c.4.1.7.5.7.9v2.3c0 1.1-.9 2-2 2A17.5 17.5 0 0 1 4.6 5.5c0-1.1.9-2 2-2z"/><path d="M20 4l-5.5 5.5M14.5 5v4.5H19"/>',
  ),
  outgoingCall(
    '<path d="M6.6 3.5h2.3c.4 0 .8.3.9.7l1 3.3c.1.4 0 .8-.3 1.1l-1.4 1.3a12 12 0 0 0 5 5l1.3-1.4c.3-.3.7-.4 1.1-.3l3.3 1c.4.1.7.5.7.9v2.3c0 1.1-.9 2-2 2A17.5 17.5 0 0 1 4.6 5.5c0-1.1.9-2 2-2z"/><path d="M14.5 9.5L20 4M15.5 4H20v4.5"/>',
  ),

  /// AppRecents row details.
  info('<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>'),

  /// AppVoicemail player (pause is the artboard's; play is its pair).
  pause('<path d="M8 5v14M16 5v14"/>'),
  play('<path d="M7.5 5l11 7-11 7z"/>'),

  /// AppVoicemail delete.
  trash('<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>'),

  /// Greeting recorder (not drawn on an artboard; the mute icon without the
  /// slash, and a stop square).
  mic(
    '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0"/><path d="M12 17.5V21"/>',
  ),
  stop('<rect x="7" y="7" width="10" height="10" rx="1.5"/>'),

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
