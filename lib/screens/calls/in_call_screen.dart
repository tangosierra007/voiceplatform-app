import 'dart:math' as math;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../calls/call_actions.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../engine/engine_provider.dart';
import '../../nav/routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_icons.dart';
import 'call_widgets.dart';

/// AppInCall: the line called, timer, Encrypted and HD tags, the live
/// waveform; Mute, Keypad (DTMF), Speaker (or the route sheet), Hold,
/// Transfer, Add call (Merge with two calls); red hang up. Ink in both themes.
class InCallScreen extends ConsumerStatefulWidget {
  const InCallScreen({super.key, required this.callId});
  final String callId;

  @override
  ConsumerState<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends ConsumerState<InCallScreen> {
  bool _keypad = false;
  String _dtmf = '';

  CallEngine get _engine => ref.read(callEngineProvider);

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callSnapshotProvider(widget.callId)).value;
    if (call == null) return const CallScaffold(child: SizedBox.expand());
    final calls = ref.watch(activeCallsProvider).value ?? const [];
    final others = [
      for (final c in calls)
        if (c.id != call.id && c.state != CallState.ended) c,
    ];
    final book = ref.watch(callBookProvider);
    final matcher = ref.watch(contactMatcherProvider);
    final local = call.remoteName == null
        ? matcher.match(call.remoteNumber)?.name
        : null;
    final audio = ref.watch(audioStateProvider).value;
    final connected = call.state == CallState.connected;
    final held = call.state == CallState.heldByMe;
    final live = connected || held || call.state == CallState.heldByRemote;
    final transfer = book.transfer;
    final isConsult = transfer != null && transfer.$2 == call.id;

    return CallScaffold(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  28,
                  24,
                  28,
                  20 + math.max(34, MediaQuery.viewPaddingOf(context).bottom),
                ),
                child: Column(
                  children: [
                    for (final o in others) ...[
                      _HeldBar(
                        call: o,
                        matcher: matcher,
                        isTransfer: isConsult && o.id == transfer.$1,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      _lineCalled(call, book),
                      textAlign: TextAlign.center,
                      style: callEyebrow(),
                    ),
                    const SizedBox(height: 10 + 18),
                    CallAvatar(name: call.remoteName ?? local, size: 96),
                    const SizedBox(height: 10 + 8),
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
                    const SizedBox(height: 10 + 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (live && call.connectedAt != null)
                          Semantics(
                            label: 'Call time',
                            child: CallTimer(since: call.connectedAt!),
                          )
                        else
                          Text(
                            _stateText(call.state),
                            style: callText(18, weight: FontWeight.w700),
                          ),
                        if (held || call.state == CallState.heldByRemote)
                          Text(
                            held ? 'On hold' : 'Held by them',
                            style: callText(
                              14,
                              weight: FontWeight.w700,
                              colour: VpCallColours.muted,
                            ),
                          ),
                        if (call.encrypted) const CallTag('ENCRYPTED'),
                        if (call.hdAudio) const CallTag('HD'),
                      ],
                    ),
                    const SizedBox(height: 10 + 6),
                    if (connected)
                      LiveWaveform(muted: call.muted)
                    else
                      const SizedBox(height: 30),
                    const Spacer(),
                    const SizedBox(height: 16),
                    if (_keypad)
                      _DtmfPad(
                        sent: _dtmf,
                        onDigit: (d) {
                          setState(() => _dtmf += d);
                          _engine.sendDtmf(call.id, d);
                        },
                        onHide: () => setState(() => _keypad = false),
                      )
                    else
                      _Controls(
                        call: call,
                        others: others,
                        audio: audio,
                        isConsult: isConsult,
                        onKeypad: connected
                            ? () => setState(() => _keypad = true)
                            : null,
                        onCompleteTransfer: isConsult
                            ? () => _engine.transferAttended(
                                transfer.$1,
                                transfer.$2,
                              )
                            : null,
                      ),
                    const SizedBox(height: 26),
                    CallControl(
                      label: '',
                      semanticLabel: 'Hang up',
                      icon: VpIcon.phone,
                      rotate: true,
                      size: 78,
                      iconSize: 30,
                      background: VpCallColours.hangUp,
                      iconColour: VpCallColours.onControl,
                      onPressed: () => _engine.hangup(call.id),
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

  /// "SALES · 03 5550 1201" for a call to a group; "MAIN · 03 5550 1200" for
  /// an outgoing call, from the caller ID it used.
  String _lineCalled(CallSnapshot c, CallBook book) {
    final info = c.incoming;
    if (c.direction == CallDirection.incoming && info != null) {
      final label = info.calledLabel?.replaceFirst(
        RegExp(r'\s+group$', caseSensitive: false),
        '',
      );
      final number = info.calledNumber == null
          ? null
          : formatAuNumber(info.calledNumber!);
      return [label, number].whereType<String>().join(' · ').toUpperCase();
    }
    final id = book.callerIds[c.id];
    if (id == null) {
      return c.direction == CallDirection.incoming
          ? 'INCOMING CALL'
          : 'CALLING';
    }
    if (id.value == 'withheld') return 'NUMBER WITHHELD';
    final name = id.label.replaceAll(RegExp(r'[\d\s+]+$'), '').trim();
    return [
      if (name.isNotEmpty) name,
      formatAuNumber(id.value),
    ].join(' · ').toUpperCase();
  }

  static String _stateText(CallState s) => switch (s) {
    CallState.dialling => 'Calling',
    CallState.ringing => 'Ringing',
    CallState.transferring => 'Transferring',
    CallState.ended => 'Call ended',
    _ => '',
  };
}

class _Controls extends ConsumerWidget {
  const _Controls({
    required this.call,
    required this.others,
    required this.audio,
    required this.isConsult,
    required this.onKeypad,
    required this.onCompleteTransfer,
  });

  final CallSnapshot call;
  final List<CallSnapshot> others;
  final AudioState? audio;
  final bool isConsult;
  final VoidCallback? onKeypad;
  final VoidCallback? onCompleteTransfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(callEngineProvider);
    final connected = call.state == CallState.connected;
    final held = call.state == CallState.heldByMe;
    final route = audio?.route ?? AudioRoute.earpiece;
    final routes =
        audio?.available ?? const {AudioRoute.earpiece, AudioRoute.speaker};
    final speakerOn = route != AudioRoute.earpiece;
    final simpleRoutes = routes.difference({
      AudioRoute.earpiece,
      AudioRoute.speaker,
    }).isEmpty;

    final controls = <Widget>[
      CallControl(
        label: 'Mute',
        icon: VpIcon.micOff,
        on: call.muted,
        onPressed: connected || held
            ? () => engine.setMuted(!call.muted)
            : null,
      ),
      CallControl(label: 'Keypad', icon: VpIcon.keypad, onPressed: onKeypad),
      CallControl(
        label: 'Speaker',
        icon: VpIcon.speaker,
        on: speakerOn,
        semanticLabel: simpleRoutes ? 'Speaker' : 'Audio: ${_routeName(route)}',
        onPressed: () => simpleRoutes
            ? engine.setAudioRoute(
                speakerOn ? AudioRoute.earpiece : AudioRoute.speaker,
              )
            : showAudioRouteSheet(context, ref, routes, route),
      ),
      CallControl(
        label: 'Hold',
        icon: VpIcon.hold,
        on: held,
        onPressed: connected
            ? () => engine.hold(call.id)
            : held
            ? () => engine.resume(call.id)
            : null,
      ),
      if (isConsult)
        CallControl(
          label: 'Complete transfer',
          icon: VpIcon.transfer,
          onPressed: onCompleteTransfer,
        )
      else
        CallControl(
          label: 'Transfer',
          icon: VpIcon.transfer,
          onPressed: connected || held
              ? () => context.push(Routes.transfer(call.id))
              : null,
        ),
      if (others.isNotEmpty && !isConsult)
        CallControl(
          label: 'Merge',
          icon: VpIcon.plus,
          onPressed: connected
              ? () => engine.merge(others.first.id, call.id)
              : null,
        )
      else
        CallControl(
          label: 'Add call',
          icon: VpIcon.plus,
          onPressed: connected && others.isEmpty
              ? () => context.go('${Routes.keypad}?add=1')
              : null,
        ),
    ];
    return CallGrid(rowGap: 22, children: controls);
  }
}

String _routeName(AudioRoute r) => switch (r) {
  AudioRoute.earpiece => 'Phone',
  AudioRoute.speaker => 'Speaker',
  AudioRoute.bluetooth => 'Bluetooth',
  AudioRoute.wiredHeadset => 'Headset',
  AudioRoute.car => 'Car',
};

/// With Bluetooth, a headset or a car: pick where the call plays.
Future<void> showAudioRouteSheet(
  BuildContext context,
  WidgetRef ref,
  Set<AudioRoute> routes,
  AudioRoute current,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in AudioRoute.values)
          if (routes.contains(r))
            ListTile(
              title: Text(_routeName(r)),
              trailing: r == current ? const Icon(Icons.check) : null,
              selected: r == current,
              onTap: () {
                ref.read(callEngineProvider).setAudioRoute(r);
                Navigator.of(context).pop();
              },
            ),
      ],
    ),
  ),
);

/// The other call: on hold, with a tap to swap to it.
class _HeldBar extends ConsumerWidget {
  const _HeldBar({
    required this.call,
    required this.matcher,
    required this.isTransfer,
  });
  final CallSnapshot call;
  final ContactMatcher matcher;
  final bool isTransfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = callTitle(
      call,
      call.remoteName == null ? matcher.match(call.remoteNumber)?.name : null,
    );
    final text = isTransfer
        ? '$name · on hold, to transfer'
        : '$name · on hold';
    return Semantics(
      button: true,
      label: '$text. Swap to this call',
      excludeSemantics: true,
      onTap: () => _swap(context, ref),
      child: Material(
        color: VpCallColours.control,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _swap(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                VpSvgIcon(VpIcon.hold, size: 18, colour: VpCallColours.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: callText(13, colour: VpCallColours.muted),
                  ),
                ),
                Text(
                  'Swap',
                  style: callText(
                    13,
                    weight: FontWeight.w700,
                    colour: VpCallColours.wave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _swap(BuildContext context, WidgetRef ref) async {
    final engine = ref.read(callEngineProvider);
    for (final c in engine.activeCalls) {
      if (c.id != call.id && c.state == CallState.connected) {
        await engine.hold(c.id);
      }
    }
    if (call.state == CallState.heldByMe) await engine.resume(call.id);
    if (context.mounted) context.go(Routes.inCall(call.id));
  }
}

/// The in-call keypad: digits go out as DTMF (RFC 4733) as they are pressed.
class _DtmfPad extends StatelessWidget {
  const _DtmfPad({
    required this.sent,
    required this.onDigit,
    required this.onHide,
  });
  final String sent;
  final ValueChanged<String> onDigit;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 30,
          child: Text(sent, style: callText(24, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        CallGrid(
          rowGap: 12,
          children: [
            for (final k in keys)
              Center(
                child: Semantics(
                  button: true,
                  label: k == '*'
                      ? 'Star'
                      : k == '#'
                      ? 'Hash'
                      : k,
                  excludeSemantics: true,
                  onTap: () => onDigit(k),
                  child: Material(
                    color: VpCallColours.control,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onDigit(k),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: Center(
                          child: Text(
                            k,
                            style: callText(26, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        TextButton(
          onPressed: onHide,
          style: TextButton.styleFrom(foregroundColor: VpCallColours.text),
          child: const Text('Hide keypad'),
        ),
      ],
    );
  }
}

/// Three columns, rows [rowGap] apart (the artboard's grid), without a
/// scrolling grid inside the screen's scroll view.
class CallGrid extends StatelessWidget {
  const CallGrid({super.key, required this.rowGap, required this.children});
  final double rowGap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var r = 0; r * 3 < children.length; r++) ...[
        if (r > 0) SizedBox(height: rowGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = r * 3; i < r * 3 + 3; i++)
              Expanded(
                child: Center(
                  child: i < children.length ? children[i] : const SizedBox(),
                ),
              ),
          ],
        ),
      ],
    ],
  );
}
