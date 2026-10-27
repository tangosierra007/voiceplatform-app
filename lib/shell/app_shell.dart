import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/version.dart';
import '../net/live_events.dart';
import '../screens/signin/update_screen.dart';
import 'shell_status.dart';
import 'vp_tab_bar.dart';

/// The tabbed part of the app: the current tab's screen over the tab bar.
/// Branch indexes follow [AppTab] order whether or not Messages is visible.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(shellStatusProvider);
    final tabs = [
      for (final t in AppTab.values)
        if (t != AppTab.messages || status.hasSmsLine) t,
    ];
    var current = AppTab.values[shell.currentIndex];
    if (!tabs.contains(current)) {
      // Messages went away (last SMS line removed): fall back to Keypad.
      current = AppTab.keypad;
      WidgetsBinding.instance.addPostFrameCallback((_) => shell.goBranch(0));
    }
    // Presence polling (the stream's fallback) runs only while Contacts is
    // open; Transfer (4.3) sets the same flag.
    final live = ref.read(liveEventsProvider);
    final onContacts = current == AppTab.contacts;
    if (live.presenceVisible != onContacts) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => live.presenceVisible = onContacts,
      );
    }
    return Scaffold(
      body: ref.watch(updateBannerProvider)
          ? Column(
              children: [
                // Between minimum and recommended versions, once a day.
                const SafeArea(bottom: false, child: UpdateBanner()),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: shell,
                  ),
                ),
              ],
            )
          : shell,
      bottomNavigationBar: VpTabBar(
        tabs: tabs,
        current: current,
        badges: {
          AppTab.recents: status.recentsBadge,
          AppTab.messages: status.messagesBadge,
        },
        onSelect: (t) {
          final index = AppTab.values.indexOf(t);
          shell.goBranch(index, initialLocation: index == shell.currentIndex);
        },
      ),
    );
  }
}
