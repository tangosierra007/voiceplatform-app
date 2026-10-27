import 'package:call_engine/call_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../calls/call_actions.dart';
import '../../calls/directory.dart';
import '../../calls/me_state.dart';
import '../../calls/numbers.dart';
import '../../engine/engine_provider.dart';
import '../../engine/fake_call_engine.dart';
import '../../nav/routes.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_icons.dart';

/// The number on the keypad, kept while you switch tabs.
final dialledProvider = NotifierProvider<DialledNotifier, String>(
  DialledNotifier.new,
);

class DialledNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

/// AppKeypad (and AppOffline): status chip, caller ID picker, the number with
/// its contact match, the keys, the orange call button with an ink icon.
class KeypadScreen extends ConsumerWidget {
  const KeypadScreen({super.key});

  static const _letters = {
    '1': '',
    '2': 'ABC',
    '3': 'DEF',
    '4': 'GHI',
    '5': 'JKL',
    '6': 'MNO',
    '7': 'PQRS',
    '8': 'TUV',
    '9': 'WXYZ',
    '*': '',
    '0': '+',
    '#': '',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final offline = ref.watch(offlineProvider);
    final number = ref.watch(dialledProvider);
    final match = ref.watch(contactMatcherProvider).match(number);
    final calls = ref.watch(activeCallsProvider).value ?? const [];
    final current = calls
        .where(
          (x) => x.state != CallState.incoming && x.state != CallState.ended,
        )
        .firstOrNull;
    final dialled = ref.read(dialledProvider.notifier);

    void press(String k) {
      HapticFeedback.selectionClick();
      if (number.length < 32) dialled.set(number + k);
    }

    Future<void> call() async {
      if (number.isEmpty) return;
      final id = await startCall(context, ref, number);
      if (id != null || isEmergencyNumber(number)) dialled.set('');
    }

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (offline) const _OfflineBanner(),
                  if (current != null) _BackToCall(call: current),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        offline ? 12 : 6,
                        20,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              _StatusChip(offline: offline),
                              const SizedBox(width: 8),
                              Expanded(child: _CallerIdChip(dim: offline)),
                            ],
                          ),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: offline ? 90 : 120,
                              ),
                              child: Center(
                                child: offline
                                    ? Text(
                                        "For 000, use your phone's own dialler.\nIt works without the app.",
                                        textAlign: TextAlign.center,
                                        style: VpType.body.copyWith(
                                          fontSize: 14,
                                          height: 20 / 14,
                                          color: c.textMuted,
                                        ),
                                      )
                                    : _Display(number: number, match: match),
                              ),
                            ),
                          ),
                          _Keys(
                            enabled: !offline,
                            onKey: press,
                            onLongZero: () => press('+'),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Expanded(child: SizedBox()),
                              Expanded(
                                child: Center(
                                  child: _CallButton(
                                    offline: offline,
                                    onPressed: offline || number.isEmpty
                                        ? null
                                        : call,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: number.isEmpty || offline
                                      ? const SizedBox(width: 48, height: 48)
                                      : Semantics(
                                          button: true,
                                          label: 'Delete',
                                          hint: 'Hold to clear',
                                          excludeSemantics: true,
                                          onTap: () => dialled.set(
                                            number.substring(
                                              0,
                                              number.length - 1,
                                            ),
                                          ),
                                          child: InkResponse(
                                            onTap: () => dialled.set(
                                              number.substring(
                                                0,
                                                number.length - 1,
                                              ),
                                            ),
                                            onLongPress: () => dialled.set(''),
                                            radius: 28,
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: Center(
                                                child: VpSvgIcon(
                                                  VpIcon.backspace,
                                                  size: 28,
                                                  colour: c.textMuted,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Display extends StatelessWidget {
  const _Display({required this.number, required this.match});
  final String number;
  final ContactMatch? match;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      liveRegion: true,
      label: number.isEmpty
          ? 'No number entered'
          : '${formatAuNumber(number)}${match == null ? '' : ', ${match!.line}'}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              number.isEmpty ? ' ' : formatAuNumber(number),
              maxLines: 1,
              style: VpType.body.copyWith(
                fontSize: 36,
                height: 1.1,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                letterSpacing: 0.72,
                color: c.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            match?.line ?? ' ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VpType.body.copyWith(fontSize: 14, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys({
    required this.enabled,
    required this.onKey,
    required this.onLongZero,
  });
  final bool enabled;
  final ValueChanged<String> onKey;
  final VoidCallback onLongZero;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
    return Column(
      children: [
        for (var r = 0; r < 4; r++) ...[
          if (r > 0) const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Center(
                    child: _Key(
                      digit: keys[r * 3 + i],
                      letters: KeypadScreen._letters[keys[r * 3 + i]]!,
                      enabled: enabled,
                      onTap: () => onKey(keys[r * 3 + i]),
                      onLongPress: keys[r * 3 + i] == '0' ? onLongZero : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.digit,
    required this.letters,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });
  final String digit;
  final String letters;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final label = switch (digit) {
      '*' => 'Star',
      '#' => 'Hash',
      '0' => '0, hold for plus',
      _ => letters.isEmpty ? digit : '$digit $letters',
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: c.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            onLongPress: enabled ? onLongPress : null,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: c.border, offset: const Offset(0, 1)),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      digit,
                      style: VpType.body.copyWith(
                        fontSize: 30,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        fontVariations: const [FontVariation('wght', 600)],
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    SizedBox(
                      height: 10,
                      child: Text(
                        letters,
                        style: VpType.body.copyWith(
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          letterSpacing: 1.4,
                          color: c.textMuted,
                        ),
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
}

/// Orange fill with an ink handset; dashed and off while offline.
class _CallButton extends StatelessWidget {
  const _CallButton({required this.offline, required this.onPressed});
  final bool offline;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    if (offline) {
      return Semantics(
        label: 'Call, unavailable while offline',
        button: true,
        enabled: false,
        excludeSemantics: true,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(color: c.borderStrong),
          ),
          child: Center(
            child: VpSvgIcon(
              VpIcon.phone,
              size: 30,
              colour: c.textMuted,
              strokeWidth: 2.2,
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Call',
      enabled: onPressed != null,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: c.brand,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 78,
            height: 78,
            child: Center(
              child: VpSvgIcon(
                VpIcon.phone,
                size: 30,
                colour: c.onBrand,
                strokeWidth: 2.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.chip`: 32 px pill, 13 px 700.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.dot,
    this.background,
    this.foreground,
    this.border,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.semantics,
  });
  final String label;
  final Color? dot;
  final Color? background;
  final Color? foreground;
  final Color? border;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final fg = foreground ?? c.text;
    return Semantics(
      button: onTap != null,
      label: semantics ?? label,
      excludeSemantics: true,
      onTap: onTap,
      // 32 px to see, 48 px to touch (Android's minimum tap target).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            color: background ?? c.surface,
            shape: StadiumBorder(
              side: BorderSide(color: border ?? c.borderStrong),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              onLongPress: onLongPress,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dot != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VpType.body.copyWith(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                            color: fg,
                          ),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 6),
                        trailing!,
                      ],
                    ],
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

class _StatusChip extends ConsumerWidget {
  const _StatusChip({required this.offline});
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    if (offline) {
      return _Chip(
        label: 'Offline',
        dot: c.borderStrong,
        background: c.surfaceRaised,
        foreground: c.textMuted,
        border: Colors.transparent,
      );
    }
    final s = ref.watch(myStatusProvider) ?? StatusStatus.available;
    final (label, bg, fg) = switch (s) {
      StatusStatus.dnd => ('Do not disturb', c.danger100, c.statusBad),
      StatusStatus.away => ('Away', c.surfaceRaised, c.textMuted),
      _ => ('Available', c.success100, c.statusOk),
    };
    return _Chip(
      label: label,
      dot: fg,
      background: bg,
      foreground: fg,
      border: Colors.transparent,
      semantics: 'Status: $label',
      onTap: () => _statusSheet(context, ref, s),
    );
  }
}

Future<void> _statusSheet(
  BuildContext context,
  WidgetRef ref,
  StatusStatus current,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (s, label) in const [
            (StatusInputStatus.available, 'Available'),
            (StatusInputStatus.dnd, 'Do not disturb'),
            (StatusInputStatus.away, 'Away'),
          ])
            ListTile(
              title: Text(label),
              selected: s.json == current.json,
              trailing: s.json == current.json ? const Icon(Icons.check) : null,
              onTap: () {
                Navigator.of(context).pop();
                ref.read(myStatusProvider.notifier).set(s).catchError((_) {});
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Your desk phone shows the same status.',
              style: VpType.small.copyWith(color: context.vp.textMuted),
            ),
          ),
        ],
      ),
    ),
  ),
);

class _CallerIdChip extends ConsumerWidget {
  const _CallerIdChip({required this.dim});
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final picked = ref.watch(selectedCallerIdProvider);
    final ids = ref.watch(callerIdsProvider).value ?? const [];
    final engine = ref.watch(callEngineProvider);
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Align(
        alignment: Alignment.centerRight,
        child: _Chip(
          label: callsShow(picked),
          semantics: '${callsShow(picked)}. Change caller ID',
          trailing: VpSvgIcon(VpIcon.chevronDown, size: 14, colour: c.text),
          onTap: dim || ids.isEmpty
              ? null
              : () => _callerIdSheet(context, ref, ids, picked),
          // Debug builds with the fake engine: hold to ring this phone with the
          // artboard's caller, to drive the call screens without SIP.
          onLongPress: kDebugMode && engine is FakeCallEngine
              ? () => simulateArtboardCall(engine)
              : null,
        ),
      ),
    );
  }
}

/// The AppIncoming caller (Westgate Supplies to the Sales group), for the
/// fake engine in debug builds.
void simulateArtboardCall(FakeCallEngine engine) => engine.simulateIncoming(
  remoteNumber: '+61355501987',
  remoteName: 'Westgate Supplies',
  info: IncomingInfo(
    calledNumber: '+61355501201',
    calledLabel: 'Sales group',
    alsoRinging: const ["Mia's desk phone"],
    repeatCount: 3,
    lastAnsweredBy: 'Tom Walsh',
    lastAnsweredAt: DateTime.now().subtract(const Duration(minutes: 30)),
  ),
);

Future<void> _callerIdSheet(
  BuildContext context,
  WidgetRef ref,
  List<CallerId> ids,
  CallerId? picked,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final id in ids)
          ListTile(
            title: Text(id.label),
            selected: id.value == picked?.value,
            trailing: id.value == picked?.value
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              ref.read(selectedCallerIdProvider.notifier).pick(id);
              Navigator.of(context).pop();
            },
          ),
      ],
    ),
  ),
);

/// AppOffline's banner: ink card, amber wifi-off, what still works.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: VpPalette.ink900,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            // Artboard #ffb35c: warning-300, the warning colour on ink.
            child: VpSvgIcon(
              VpIcon.wifiOff,
              size: 20,
              colour: VpPalette.warning300,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              const TextSpan(
                children: [
                  TextSpan(
                    text: 'No internet on this phone\n',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontVariations: [FontVariation('wght', 700)],
                    ),
                  ),
                  TextSpan(
                    text: "The app can't make or take calls right now. Calls to you ring your desk phone, then voicemail. We'll reconnect by ourselves.",
                  ),
                ],
              ),
              style: VpType.body.copyWith(
                fontSize: 13,
                height: 19 / 13,
                color: VpPalette.grey100,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A call is going on: a strip to go back to it (Add call puts the first on
/// hold while you dial).
class _BackToCall extends ConsumerWidget {
  const _BackToCall({required this.call});
  final CallSnapshot call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final m = call.remoteName == null
        ? ref.watch(contactMatcherProvider).match(call.remoteNumber)?.name
        : null;
    final name = call.remoteName ?? m ?? formatAuNumber(call.remoteNumber);
    final held = call.state == CallState.heldByMe;
    final text = held ? '$name · on hold' : '$name · on a call';
    return Semantics(
      button: true,
      label: '$text. Back to the call',
      excludeSemantics: true,
      onTap: () => context.go(Routes.inCall(call.id)),
      child: Material(
        color: c.brandTint,
        child: InkWell(
          onTap: () => context.go(Routes.inCall(call.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VpType.bodyStrong.copyWith(color: c.text),
                  ),
                ),
                Text(
                  'Back to call',
                  style: VpType.bodyStrong.copyWith(color: c.brandText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
