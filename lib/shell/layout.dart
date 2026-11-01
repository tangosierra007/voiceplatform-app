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
