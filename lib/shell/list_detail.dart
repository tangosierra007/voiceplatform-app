import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'layout.dart';

/// The wide layout's list and detail (FoldRecents, FoldContacts,
/// FoldMessages): the list on the left on the surface with a 1 px right
/// border, [listPaneWidth] wide (360 dp when there's room, down to 280),
/// the selected item filling the rest on the canvas.
class ListDetailLayout extends StatelessWidget {
  const ListDetailLayout({super.key, required this.list, required this.detail});

  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: listPaneWidth(box.maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(right: BorderSide(color: c.border)),
              ),
              // Filter chips scroll sideways at large text; they never paint
              // over the detail.
              child: ClipRect(child: list),
            ),
          ),
          Expanded(child: detail),
        ],
      ),
    );
  }
}

/// The item the person picked in a tab's list, kept across fold, unfold and
/// rotation (in memory, for this run of the app). Null when they haven't
/// picked one, or went back to the list: the wide layout then shows the
/// first item beside the list, and the phone layout shows the list.
class PickedNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void pick(String? id) => state = id;
}

/// Calls [onChange] after a frame whenever the window crosses the
/// [listDetailMinWidth] switch (not on the first build). For moving a picked
/// item between its own full-screen page and the pane beside the list.
class LayoutSwitchListener extends StatefulWidget {
  const LayoutSwitchListener({
    super.key,
    required this.onChange,
    required this.child,
  });

  final void Function(bool wide) onChange;
  final Widget child;

  @override
  State<LayoutSwitchListener> createState() => _LayoutSwitchListenerState();
}

class _LayoutSwitchListenerState extends State<LayoutSwitchListener> {
  bool? _wide;

  @override
  Widget build(BuildContext context) {
    final wide = isListDetailLayout(context);
    if (_wide != null && _wide != wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChange(wide);
      });
    }
    _wide = wide;
    return widget.child;
  }
}
