import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/version.dart';
import '../../net/api.dart';
import '../../platform/phone.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';

const _playListing =
    'https://play.google.com/store/apps/details?id=au.com.voiceplatform.app';

/// AppUpdate: below the minimum version (APP7). Blocking: no back, no other
/// route while it holds.
class UpdateScreen extends ConsumerWidget {
  const UpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final version = ref.watch(apiConfigProvider).appVersion;
    final store = ref.watch(updateRequiredProvider)?.storeUrl ?? _playListing;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      32,
                      90,
                      32,
                      20 + vpBottomInset(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        VpIconTile(
                          icon: VpIcon.update,
                          size: 72,
                          radius: 20,
                          iconSize: 34,
                          background: c.brandTint,
                          colour: c.brandText,
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            'Update to keep calling',
                            textAlign: TextAlign.center,
                            style: vpTitle(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'This version ($version) can no longer make or take calls. '
                          'The update takes about a minute. Calls ring your desk phone in the meantime.',
                          textAlign: TextAlign.center,
                          style: vpMuted(context),
                        ),
                        const Spacer(),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: VpButton(
                            label: 'Update now',
                            onPressed: () =>
                                ref.read(phoneLauncherProvider).openUrl(store),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "For emergencies, use your phone's dialler.",
                          textAlign: TextAlign.center,
                          // 12 px on the artboard's inherited 22 px line.
                          style: vpMuted(context, size: 12, line: 22),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Between the minimum and recommended versions: once a day, dismissible.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(updateBannerProvider)) return const SizedBox.shrink();
    final c = context.vp;
    final store = ref.watch(appConfigProvider)?.storeUrl ?? _playListing;
    final banner = ref.read(updateBannerProvider.notifier);
    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: c.info100,
          borderRadius: BorderRadius.circular(VpRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'A new version of the app is ready.',
                style: VpType.small.copyWith(color: c.text),
              ),
            ),
            TextButton(
              onPressed: () {
                banner.dismiss();
                ref.read(phoneLauncherProvider).openUrl(store);
              },
              child: const Text('Update'),
            ),
            TextButton(
              onPressed: banner.dismiss,
              style: TextButton.styleFrom(foregroundColor: c.text),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
