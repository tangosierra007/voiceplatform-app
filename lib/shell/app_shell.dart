import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/version.dart';
import '../calls/me_state.dart';
import '../net/api.dart';
import '../net/live_events.dart';
import '../screens/signin/update_screen.dart';
import 'layout.dart';
import 'me_failed_banner.dart';
import 'shell_status.dart';
import 'vp_nav_rail.dart';
import 'vp_tab_bar.dart';

/// The tabbed part of the app: the current tab's screen with the tab bar
/// below it, or, at 600 dp and wider ([isWideLayout]), the navigation rail
/// on its left. Branch indexes follow [AppTab] order whether or not Messages
/// is visible.
///
/// Folding, unfolding or rotating only moves the bar to the rail and back:
/// go_router keeps the [StatefulNavigationShell] and its branch navigators
/// under its own keys, so their state (open tab, pushed pages, scroll
/// positions, half-typed text) carries over wherever the shell sits.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get shell => widget.shell;

  @override
  Widget build(BuildContext context) {
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
    final badges = {
      AppTab.recents: status.recentsBadge,
      AppTab.messages: status.messagesBadge,
    };
    void select(AppTab t) {
      final index = AppTab.values.indexOf(t);
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
    }

    final wide = isWideLayout(context);
    Widget screens = Column(
      children: [
        if (updateBanner || meBanner)
          SafeArea(
            bottom: false,
            left: !wide,
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
            removeTop: updateBanner || meBanner,
            child: shell,
          ),
        ),
      ],
    );
    if (!wide) {
      return Scaffold(
        body: screens,
        bottomNavigationBar: VpTabBar(
          tabs: tabs,
          current: current,
          badges: badges,
          onSelect: select,
        ),
      );
    }
    // Wide: the rail takes the left inset; the screens keep the rest. With
    // no tab bar under them, they keep clear of the bottom inset themselves.
    screens = MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      child: SafeArea(top: false, left: false, right: false, child: screens),
    );
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VpNavRail(
            tabs: tabs,
            current: current,
            badges: badges,
            onSelect: select,
          ),
          Expanded(child: screens),
        ],
      ),
    );
  }
}
