import 'dart:math' as math;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_provider.dart';
import '../platform/phone.dart';
import '../theme/app_theme.dart';
import '../widgets/vp_controls.dart';
import '../widgets/vp_icons.dart';

/// The number to put in the phone's dialler: the three emergency digits, with
/// any trunk-access 0 dropped (0000 dials 000).
String emergencyDialString(String dialled) {
  final digits = dialled.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length == 4 && digits.startsWith('0')
      ? digits.substring(1)
      : digits;
}

/// The one way any screen (keypad, Recents, contacts, links) places a call.
/// Emergency numbers never reach the engine: they open AppEmergency, which
/// hands them to the phone's own dialler (decision 139, amended 27 Oct; APP6).
Future<String?> dialNumber(
  BuildContext context,
  WidgetRef ref,
  String number, {
  String? callerId,
}) async {
  if (isEmergencyNumber(number)) {
    await showEmergencySheet(context, number);
    return null;
  }
  try {
    return await ref.read(callEngineProvider).call(number, callerId: callerId);
  } on EmergencyNumberUseDialler {
    // The engine applies the same rule; never place it, show the sheet.
    if (context.mounted) await showEmergencySheet(context, number);
    return null;
  }
}

/// AppEmergency, over the screen the number was dialled from.
Future<void> showEmergencySheet(BuildContext context, String dialled) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Over the whole screen, tab bar included, as the artboard draws it.
    useRootNavigator: true,
    useSafeArea: true,
    // rgba(20,17,15,.45): ink-900 at 45 %, as the artboard dims the keypad.
    barrierColor: VpPalette.ink900.withValues(alpha: 0.45),
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => EmergencySheet(dialled: dialled),
  );
}

class EmergencySheet extends ConsumerStatefulWidget {
  const EmergencySheet({super.key, required this.dialled});
  final String dialled;

  @override
  ConsumerState<EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends ConsumerState<EmergencySheet> {
  late final Future<bool> _canDial = ref.read(phoneLauncherProvider).canDial();

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final number = emergencyDialString(widget.dialled);
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
                icon: VpIcon.siren,
                size: 56,
                radius: 16,
                iconSize: 28,
                background: c.danger100,
                colour: c.statusBad,
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(
                "Emergency calls use your phone's own network",
                style: vpTitle(context, size: 24, line: 30),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Calls to 000, 112 and 106 go straight through your mobile '
              'network, so they connect even if the internet drops and '
              'emergency services get your location.',
              style: vpMuted(context),
            ),
            const SizedBox(height: 14),
            FutureBuilder<bool>(
              future: _canDial,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 58);
                }
                if (snap.data != true) return const _NoDialler();
                return _CallNowButton(
                  number: number,
                  onPressed: () async {
                    await ref.read(phoneLauncherProvider).openDialler(number);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              },
            ),
            const SizedBox(height: 14),
            VpButton(
              label: 'Cancel',
              kind: VpButtonKind.ghost,
              large: false,
              height: VpSize.controlHeight,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// The red "Call 000 now": danger-600 with white, Unbounded 800 17 px.
class _CallNowButton extends StatelessWidget {
  const _CallNowButton({required this.number, required this.onPressed});
  final String number;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = 'Call $number now';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: VpPalette.danger600,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const VpSvgIcon(
                  VpIcon.phone,
                  size: 22,
                  colour: VpPalette.white,
                  strokeWidth: 2.2,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: VpFonts.headline,
                      fontSize: 17,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      fontVariations: [FontVariation('wght', 800)],
                      color: VpPalette.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tablet or a phone with no dialler: say so plainly, offer nothing.
class _NoDialler extends StatelessWidget {
  const _NoDialler();

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.danger100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "This device can't make emergency calls. Use a mobile phone or a desk "
        'phone to call 000.',
        style: VpType.bodyStrong.copyWith(color: c.text),
      ),
    );
  }
}
