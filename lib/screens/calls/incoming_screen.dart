import 'dart:math' as math;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/call_actions.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../engine/engine_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_icons.dart';
import 'call_widgets.dart';
import 'microphone_sheet.dart';

/// AppIncoming: which number or group was called, who else is ringing, the
/// repeat-caller pill and "Last answered by", then Decline, To voicemail and
/// Answer. Ink in both themes. A phone contact's name shows on the device
/// only (APP12).
class IncomingScreen extends ConsumerWidget {
  const IncomingScreen({super.key, required this.callId});
  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callSnapshotProvider(callId)).value;
    if (call == null) return const CallScaffold(child: SizedBox.expand());
    final engine = ref.read(callEngineProvider);
    final local = call.remoteName == null
        ? ref.watch(contactMatcherProvider).match(call.remoteNumber)?.name
        : null;
    final info = call.incoming;
    final now = ref.read(clockProvider)();
    final label = info?.calledLabel;
    final shortLabel = label?.replaceFirst(
      RegExp(r'\s+group$', caseSensitive: false),
      '',
    );

    String? calledLine() {
      final parts = <String>[];
      if (info?.calledNumber != null) {
        parts.add(
          'Called ${formatAuNumber(info!.calledNumber!)}${shortLabel == null ? '' : ' $shortLabel'}.',
        );
      } else if (shortLabel != null) {
        parts.add('Called $shortLabel.');
      }
      final also = info?.alsoRinging ?? const [];
      if (also.isNotEmpty) parts.add('Also ringing ${_list(also)}.');
      return parts.isEmpty ? null : parts.join(' ');
    }

    final called = calledLine();
    final repeat = info?.repeatCount;
    final lastBy = info?.lastAnsweredBy;
    final lastAt = info?.lastAnsweredAt;

    return CallScaffold(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  28,
                  40,
                  28,
                  40 + math.max(34, MediaQuery.viewPaddingOf(context).bottom),
                ),
                child: Column(
                  children: [
                    Text(
                      label == null
                          ? 'INCOMING CALL'
                          : 'INCOMING · ${label.toUpperCase()}',
                      textAlign: TextAlign.center,
                      style: callEyebrow(),
                    ),
                    const SizedBox(height: 10 + 40),
                    CallAvatar(
                      name: call.remoteName ?? local,
                      size: 112,
                      rings: true,
                    ),
                    const SizedBox(height: 10 + 30),
                    Semantics(
                      header: true,
                      child: Text(
                        callTitle(call, local),
                        textAlign: TextAlign.center,
                        style: callName,
                      ),
                    ),
                    if (callSubtitle(call, local) case final sub?) ...[
                      const SizedBox(height: 10),
                      Text(
                        sub,
                        style: callText(16, colour: VpCallColours.soft),
                      ),
                    ],
                    if (called != null) ...[
                      const SizedBox(height: 10 + 6),
                      Text(
                        called,
                        textAlign: TextAlign.center,
                        style: callText(
                          14,
                          colour: VpCallColours.muted,
                          height: 20 / 14,
                        ),
                      ),
                    ],
                    if ((repeat ?? 0) >= 2 || lastBy != null) ...[
                      const SizedBox(height: 10 + 18),
                      if ((repeat ?? 0) >= 2)
                        RepeatCallerPill(
                          text: '${ordinal(repeat!)} call this week',
                          dark: true,
                        ),
                      if (lastBy != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          lastAt == null
                              ? 'Last answered by $lastBy'
                              : 'Last answered by $lastBy, ${whenShort(lastAt, now)}',
                          textAlign: TextAlign.center,
                          style: callText(13, colour: VpCallColours.muted),
                        ),
                      ],
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CallControl(
                            label: 'Decline',
                            icon: VpIcon.phone,
                            rotate: true,
                            iconSize: 30,
                            background: VpCallColours.hangUp,
                            iconColour: VpCallColours.onControl,
                            onPressed: () => engine.decline(callId),
                          ),
                          CallControl(
                            label: 'To voicemail',
                            icon: VpIcon.voicemail,
                            iconSize: 28,
                            onPressed: () => engine.toVoicemail(callId),
                          ),
                          CallControl(
                            label: 'Answer',
                            icon: VpIcon.phone,
                            iconSize: 30,
                            background: VpCallColours.answer,
                            iconColour: VpCallColours.onControl,
                            onPressed: () => _answer(context, ref),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The microphone is asked for when a call starts: answering is one.
  /// Refused: AppMicrophone with the steps to Settings (no desk phone option
  /// for an incoming call); back with it on, the call is answered.
  Future<void> _answer(BuildContext context, WidgetRef ref) async {
    final mic = ref.read(micPermissionProvider);
    final number =
        ref
            .read(callEngineProvider)
            .activeCalls
            .where((c) => c.id == callId)
            .firstOrNull
            ?.remoteNumber ??
        '';
    Future<void> refused() async {
      if (context.mounted) {
        await showMicrophoneSheet(
          context,
          number: number,
          answerCallId: callId,
        );
      }
    }

    if (!await mic.isGranted() && !await mic.request()) return refused();
    await mic.requestBluetooth();
    try {
      await ref.read(callEngineProvider).answer(callId);
    } on MicrophoneDenied {
      await refused();
    }
  }

  static String _list(List<String> items) => items.length == 1
      ? items.single
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

/// "3rd call this week": the amber outline pill (DESIGN_SYSTEM_app-sections,
/// Repeat callers). Dark screens: #e0b25c text on a #5a4a2a outline; light
/// screens: #7a4f00 text, #fff4e0 fill, #c98a2b outline.
class RepeatCallerPill extends StatelessWidget {
  const RepeatCallerPill({super.key, required this.text, required this.dark});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: dark ? null : VpRepeatCallerColours.lightFill,
      border: Border.all(
        color: dark
            ? VpRepeatCallerColours.darkBorder
            : VpRepeatCallerColours.lightBorder,
      ),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: callText(
        13,
        weight: FontWeight.w700,
        colour: dark
            ? VpRepeatCallerColours.darkText
            : VpRepeatCallerColours.lightText,
      ),
    ),
  );
}
