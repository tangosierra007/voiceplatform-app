import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/version.dart';
import '../calls/me_state.dart';
import '../net/api.dart';
import '../net/live_events.dart';
import '../screens/signin/update_screen.dart';
import 'me_failed_banner.dart';
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
    var current = AppTab.values[shell.currentIndex];
    final tabs = status.tabs;
    if (!tabs.contains(current)) {
      // Messages went away (last SMS line removed): fall back to Keypad.
      current = AppTab.keypad;
      WidgetsBinding.instance.addPostFrameCallback((_) => shell.goBranch(0));
    }
    ref.watch(meRetryOnResumeProvider);
    // Back online with `GET /me` still failed: ask again (Riverpod's own
    // retries stop after about a minute).
    ref.listen(offlineProvider, (was, offline) {
      if (was == true && !offline && ref.read(shellStatusProvider).meFailed) {
        ref.invalidate(meProvider);
      }
    });
    // Presence polling (the stream's fallback) runs only while Contacts is
    // open; Transfer (4.3) sets the same flag.
    final live = ref.read(liveEventsProvider);
    final onContacts = current == AppTab.contacts;
    if (live.presenceVisible != onContacts) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => live.presenceVisible = onContacts,
      );
    }
    // On Keypad while offline, AppOffline's own banner already says it.
    final meBanner =
        status.meFailed &&
        !(current == AppTab.keypad && ref.watch(offlineProvider));
    final updateBanner = ref.watch(updateBannerProvider);
    return Scaffold(
      body: updateBanner || meBanner
          ? Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // Between minimum and recommended versions, once a day.
                      if (updateBanner) const UpdateBanner(),
                      if (meBanner) MeFailedBanner(status: status),
                    ],
                  ),
                ),
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
