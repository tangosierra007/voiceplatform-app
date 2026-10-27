import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calls/call_actions.dart';
import '../../calls/numbers.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';

/// AppMicrophone, over the keypad: the microphone was refused when a call
/// started. Steps to Settings (the call starts when you come back with it
/// on), or "Call from my desk phone instead" (A1).
Future<void> showMicrophoneSheet(
  BuildContext context, {
  required String number,
  CallerId? callerId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  useSafeArea: true,
  barrierColor: VpPalette.ink900.withValues(alpha: 0.45),
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: (_) => MicrophoneSheet(number: number, callerId: callerId),
);

class MicrophoneSheet extends ConsumerStatefulWidget {
  const MicrophoneSheet({super.key, required this.number, this.callerId});
  final String number;
  final CallerId? callerId;

  @override
  ConsumerState<MicrophoneSheet> createState() => _MicrophoneSheetState();
}

class _MicrophoneSheetState extends ConsumerState<MicrophoneSheet> {
  late final AppLifecycleListener _listener;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Back from Settings with the microphone on: the call starts.
    _listener = AppLifecycleListener(onResume: _retry);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (!await ref.read(micPermissionProvider).isGranted() || !mounted) return;
    final read = ProviderScope.containerOf(context).read;
    final root = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    if (root.mounted) {
      await startCallWith(root, read, widget.number, callerId: widget.callerId);
    }
  }

  Future<void> _deskPhone() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final desk = await ref.read(deskPhoneCallProvider)(
        widget.number,
        widget.callerId,
      );
      if (!mounted) return;
      setState(
        () => _message =
            '$desk is ringing. Pick it up to call ${formatAuNumber(widget.number)}.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = "Couldn't reach your desk phone. Check it's plugged in, then try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                icon: VpIcon.micOff,
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
                'Let the app use the microphone',
                style: vpTitle(context, size: 24, line: 30),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "Without it, people can't hear you on calls. It's only used during a call, never in the background.",
              style: vpMuted(context),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text.rich(
                const TextSpan(
                  children: [
                    TextSpan(
                      text: 'In Settings:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontVariations: [FontVariation('wght', 700)],
                      ),
                    ),
                    TextSpan(
                      text: ' VoicePlatform, then turn on Microphone. Come back here and the call starts.',
                    ),
                  ],
                ),
                style: VpType.body.copyWith(
                  fontSize: 14,
                  height: 21 / 14,
                  color: c.text,
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: VpType.bodyStrong.copyWith(color: c.text),
                ),
              ),
            ],
            const SizedBox(height: 14),
            VpButton(
              label: 'Open Settings',
              onPressed: () => ref.read(micPermissionProvider).openSettings(),
            ),
            const SizedBox(height: 14),
            VpButton(
              label: 'Call from my desk phone instead',
              kind: VpButtonKind.ghost,
              large: false,
              height: VpSize.controlHeight,
              busy: _busy,
              onPressed: _deskPhone,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
