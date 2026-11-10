import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/full_screen_access.dart';
import '../engine/phone_extras.dart';
import '../theme/app_theme.dart';
import '../widgets/vp_controls.dart';
import '../widgets/vp_icons.dart';

/// Full-screen notifications are off (Android 14+): a call to a locked phone
/// rings only as a notification. "Open settings" goes to Android's page for
/// them; back with them on, the sheet closes by itself.
Future<void> showFullScreenSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      barrierColor: VpPalette.ink900.withValues(alpha: 0.45),
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => const FullScreenSheet(),
    );

class FullScreenSheet extends ConsumerWidget {
  const FullScreenSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(fullScreenAccessProvider, (_, allowed) {
      if (allowed) Navigator.of(context).maybePop();
    });
    final c = context.vp;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        10 + math.max(0, MediaQuery.viewPaddingOf(context).bottom - 10),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: VpIconTile(
                icon: VpIcon.lock,
                size: 56,
                radius: 16,
                iconSize: 28,
                background: c.brandTint,
                colour: c.brandText,
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(
                'Let calls show on your locked screen',
                style: vpTitle(context, size: 24, line: 30),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Without this, a call to a locked phone shows only as a '
              'notification, and you can miss it.',
              style: vpMuted(context),
            ),
            const SizedBox(height: 24),
            VpButton(
              label: 'Open settings',
              onPressed: () =>
                  ref.read(phoneExtrasProvider).openFullScreenSettings(),
            ),
            const SizedBox(height: 14),
            VpButton(
              label: 'Not now',
              kind: VpButtonKind.ghost,
              large: false,
              height: VpSize.controlHeight,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
