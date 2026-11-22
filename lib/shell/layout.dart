import 'package:flutter/widgets.dart';

/// The rail and the splits of APP_DESIGN_SCOPE "Screen sizes and folding
/// phones" (TJ, 2 Nov): all decided by the window's current width in dp,
/// never the device model, and all in this one file.

/// The phone layout with the tab bar below this; the navigation rail from
/// it.
const double wideLayoutMinWidth = 600;

/// True when the window is at least [wideLayoutMinWidth] wide right now. It
/// changes on fold, unfold, rotation and window resizing.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

/// The navigation rail's width (Fold artboards, `nav.frail`).
const double railWidth = 80;

/// List and detail side by side (Recents, Contacts, Messages) only when,
/// next to the rail, the list gets at least [listMinWidth] and the detail at
/// least [detailMinWidth]. The list grows to [listMaxWidth] when there's
/// room; the detail takes the rest.
const double listMinWidth = 280;
const double listMaxWidth = 360;
const double detailMinWidth = 320;

/// The narrowest window that splits: 80 + 280 + 320 = 680 dp. A Galaxy Z
/// Fold5 (690) and Fold6 (744), a Pixel Fold (701) and a Pixel 9 Pro Fold
/// (851) all split in portrait; narrower wide windows keep the phone's
/// list-then-detail flow beside the rail.
const double listDetailMinWidth = railWidth + listMinWidth + detailMinWidth;

/// True when the window shows list and detail side by side right now.
bool isListDetailLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= listDetailMinWidth;

/// The list's width beside the rail, for [available] dp (the window less the
/// rail): [listMaxWidth] when the detail still gets [detailMinWidth], down
/// to [listMinWidth].
double listPaneWidth(double available) =>
    (available - detailMinWidth).clamp(listMinWidth, listMaxWidth);

/// Keypad and in call (FoldKeypad, FoldInCall; TJ, 2 Nov): the keypad or
/// the call stays phone width, [phonePaneMaxWidth] when there's room, down
/// to [phonePaneMinWidth], never stretched; the side (the keypad's matches,
/// the call's details) takes the rest, and shows only when it gets at least
/// [phoneSideMinWidth]. Next to the rail that is 80 + 360 + 240 = 680 dp,
/// the same window as [listDetailMinWidth]; a call has no rail, so it
/// splits from 600 dp.
const double phonePaneMaxWidth = 420;
const double phonePaneMinWidth = 360;
const double phoneSideMinWidth = 240;

/// The keypad's or call's width and the side's, for [available] dp (the
/// window less the rail, if any), or null when the side would be under
/// [phoneSideMinWidth]: then the keypad or call is phone width
/// ([phonePaneMaxWidth] at most) and centred, as on the phone.
({double phone, double side})? phonePaneSplit(double available) {
  final phone = (available - phoneSideMinWidth).clamp(
    phonePaneMinWidth,
    phonePaneMaxWidth,
  );
  final side = available - phone;
  return side < phoneSideMinWidth ? null : (phone: phone, side: side);
}

/// The Keypad's short layout (FU56, Q309-4, task 401): one control row and
/// More, the keys with the call button beside the bottom row. Used when the
/// Keypad's own height is under this, that is whenever the normal layout
/// would scroll to show the call button (and, in the wide layout, the
/// emergency note under it).
///
/// The numbers are where the normal layout's call button (or note) ends,
/// measured with the bundled fonts and rounded up; test/screens/
/// short_keypad_test.dart fails if the normal layout grows past them. Online:
/// 624 dp on the phone, 700 at 200 % text; 656 to 689 with the note, 780 at
/// 200 %. Offline the banner adds 81 dp at 100 % and grows fast with the
/// text, so from 150 % offline is always short. The back-to-call strip adds
/// its own height.
///
/// [textScale] is the text scale at 13 px (the keypad chips' own measure);
/// "large" is 150 % and up, where the chips stack.
double keypadShortBelow({
  required double textScale,
  required bool note,
  bool offline = false,
  bool inCall = false,
}) {
  final large = textScale >= 1.5;
  if (offline && large) return double.infinity;
  var below = switch ((large, note && !offline)) {
    (false, false) => 630.0,
    (true, false) => 704.0,
    (false, true) => 692.0,
    (true, true) => 784.0,
  };
  if (offline) below += 76 + 230 * (textScale - 1);
  if (inCall) below += 20 + 24 * textScale;
  return below;
}
