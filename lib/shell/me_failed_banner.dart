import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/api.dart';
import '../theme/app_theme.dart';
import '../widgets/vp_icons.dart';
import 'shell_status.dart';

/// `GET /me` failed with no answer held: said on every tab, so the tab set
/// never looks confident when it isn't. Drawn as AppOffline's banner (ink
/// card, amber icon, grey text). No artboard has this state; the copy
/// follows the sign-in screens' "Can't reach VoicePlatform".
class MeFailedBanner extends ConsumerWidget {
  const MeFailedBanner({super.key, required this.status});

  final ShellStatus status;

  static const title = "Can't reach VoicePlatform";
  static const unknownTabs = 'Some tabs may be missing until the app connects.';
  static const knownTabs =
      'Your tabs are as this phone last saw them. Details may be out of date.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = status.tabsKnown ? knownTabs : unknownTabs;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: VpPalette.ink900,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: VpSvgIcon(
                VpIcon.wifiOff,
                size: 20,
                colour: VpPalette.warning300,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: '$title\n',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontVariations: [FontVariation('wght', 700)],
                      ),
                    ),
                    TextSpan(text: body),
                  ],
                ),
                style: VpType.body.copyWith(
                  fontSize: 13,
                  height: 19 / 13,
                  color: VpPalette.grey100,
                ),
              ),
            ),
            Semantics(
              container: true,
              button: true,
              label: 'Try again',
              onTap: () => ref.invalidate(meProvider),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => ref.invalidate(meProvider),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    minWidth: 48,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        'Try again',
                        maxLines: 1,
                        style: VpType.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          color: VpPalette.grey100,
                          decoration: TextDecoration.underline,
                          decorationColor: VpPalette.grey100,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
