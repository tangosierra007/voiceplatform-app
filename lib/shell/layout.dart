import 'package:flutter/widgets.dart';

/// The one layout switch (APP_DESIGN_SCOPE "Screen sizes and folding
/// phones"): the window's current width in dp, never the device model.
/// Under it, the phone layout with the tab bar; at it and wider, the wide
/// layout with the navigation rail.
const double wideLayoutMinWidth = 600;

/// True when the window is at least [wideLayoutMinWidth] wide right now. It
/// changes on fold, unfold, rotation and window resizing.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

/// The narrowest window that shows a list and its detail side by side: the
/// rail (80), the list (360) and a detail pane at least as wide as the list
/// (360). Between [wideLayoutMinWidth] and this, a tab with a list keeps the
/// phone's one-at-a-time flow beside the rail: at exactly 600 dp a 360 dp
/// list would leave 160 dp for the detail. Proposed to mobile-lead; not in
/// APP_DESIGN_SCOPE yet.
const double listDetailMinWidth = 800;

/// True when the window shows list and detail side by side right now.
bool isListDetailLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= listDetailMinWidth;
