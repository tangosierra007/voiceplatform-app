import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_provider.dart';
import '../theme/app_theme.dart';

/// Stand-ins for AppIncoming and AppInCall (4.3). They already keep the rules
/// those screens follow: ink ground in both themes, answer green and hang up
/// red with white icons, and they drive the engine for real.
class IncomingCallPlaceholder extends ConsumerWidget {
  const IncomingCallPlaceholder({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(callEngineProvider);
    final call = ref.watch(callSnapshotProvider(callId)).value;
    return _CallScaffold(
      title: call?.remoteName ?? call?.remoteNumber ?? '',
      subtitle: call?.remoteName == null ? null : call?.remoteNumber,
      controls: [
        CallControlButton(
          label: 'Decline',
          colour: VpCallColours.hangUp,
          icon: Icons.call_end,
          onPressed: () => engine.decline(callId),
        ),
        CallControlButton(
          label: 'Answer',
          colour: VpCallColours.answer,
          icon: Icons.call,
          onPressed: () => engine.answer(callId),
        ),
      ],
    );
  }
}

class InCallPlaceholder extends ConsumerWidget {
  const InCallPlaceholder({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(callEngineProvider);
    final call = ref.watch(callSnapshotProvider(callId)).value;
    return _CallScaffold(
      title: call?.remoteName ?? call?.remoteNumber ?? '',
      subtitle: call == null ? null : _stateText(call.state),
      controls: [
        CallControlButton(
          label: 'Hang up',
          colour: VpCallColours.hangUp,
          icon: Icons.call_end,
          onPressed: () => engine.hangup(callId),
        ),
      ],
    );
  }

  static String _stateText(CallState s) => switch (s) {
    CallState.dialling => 'Calling',
    CallState.ringing => 'Ringing',
    CallState.heldByMe || CallState.heldByRemote => 'On hold',
    CallState.ended => 'Call ended',
    _ => '',
  };
}

class _CallScaffold extends StatelessWidget {
  const _CallScaffold({
    required this.title,
    this.subtitle,
    required this.controls,
  });

  final String title;
  final String? subtitle;
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.callScreen(),
      child: Builder(
        builder: (context) {
          final text = Theme.of(context).textTheme;
          return Scaffold(
            backgroundColor: VpCallColours.background,
            body: SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  Text(
                    title,
                    style: text.headlineMedium?.copyWith(
                      color: VpCallColours.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: text.bodyMedium?.copyWith(
                        color: VpCallColours.text,
                      ),
                    ),
                  const Spacer(flex: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: VpSpace.s7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: controls,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A round call control: answer green or hang up red, white icon.
class CallControlButton extends StatelessWidget {
  const CallControlButton({
    super.key,
    required this.label,
    required this.colour,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Color colour;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: colour,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 68,
                height: 68,
                child: Icon(icon, color: VpCallColours.onControl, size: 30),
              ),
            ),
          ),
          const SizedBox(height: VpSpace.s2),
          Text(
            label,
            style: const TextStyle(
              color: VpCallColours.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
