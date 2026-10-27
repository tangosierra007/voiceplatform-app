import 'dart:math' as math;

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../calls/call_actions.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../engine/engine_provider.dart';
import '../../net/api.dart';
import '../../net/live_events.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import 'call_widgets.dart';

/// AppTransfer: the caller waits on hold; pick a colleague (team and live
/// presence), then "Talk to `<name>` first" (attended) or "Send now" (blind).
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key, required this.callId});
  final String callId;

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final _query = TextEditingController();
  Colleague? _picked;
  late final LiveEvents _live = ref.read(liveEventsProvider);

  @override
  void initState() {
    super.initState();
    // The caller waits on hold while you choose, as the artboard shows.
    final c = _call();
    if (c?.state == CallState.connected) {
      ref.read(callEngineProvider).hold(widget.callId);
    }
    // Presence polling (the stream's fallback) runs while Transfer is open.
    _live.presenceVisible = true;
  }

  @override
  void dispose() {
    _live.presenceVisible = false;
    _query.dispose();
    super.dispose();
  }

  CallSnapshot? _call() => ref
      .read(callEngineProvider)
      .activeCalls
      .where((c) => c.id == widget.callId)
      .firstOrNull;

  Future<void> _cancel() async {
    final c = _call();
    if (c?.state == CallState.heldByMe) {
      await ref.read(callEngineProvider).resume(widget.callId);
    }
    if (mounted) context.pop();
  }

  Future<void> _sendNow() async {
    final p = _picked;
    if (p == null) return;
    await ref
        .read(callEngineProvider)
        .transferBlind(widget.callId, p.extensionValue);
  }

  Future<void> _talkFirst() async {
    final p = _picked;
    if (p == null) return;
    final consult = await startCall(context, ref, p.extensionValue);
    if (consult != null) {
      ref.read(callBookProvider.notifier).startTransfer(widget.callId, consult);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final outer = Theme.of(context);
    final call = ref.watch(callSnapshotProvider(widget.callId)).value;
    final colleagues = ref.watch(colleaguesProvider).value ?? const [];
    final presence = ref.watch(presenceProvider);
    final matcher = ref.watch(contactMatcherProvider);
    final local = call == null || call.remoteName != null
        ? null
        : matcher.match(call.remoteNumber)?.name;
    final caller = call == null ? '' : callTitle(call, local);
    final first = caller.split(' ').first;
    final q = _query.text.trim().toLowerCase();
    final shown = [
      for (final col in colleagues)
        if (q.isEmpty ||
            col.name.toLowerCase().contains(q) ||
            col.extensionValue.contains(q) ||
            (col.mobile != null &&
                nationalDigits(col.mobile!).contains(nationalDigits(q))))
          col,
    ];

    return CallScaffold(
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: call?.connectedAt == null
                  ? Text(
                      '$caller · on hold',
                      style: callText(13, colour: VpCallColours.muted),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$caller · ',
                            style: callText(13, colour: VpCallColours.muted),
                          ),
                          CallTimer(
                            since: call!.connectedAt!,
                            style: callText(13, colour: VpCallColours.muted),
                          ),
                          Text(
                            ' · on hold',
                            style: callText(13, colour: VpCallColours.muted),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.canvas,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Theme(
                // The sheet follows the app's theme; only the strip above is ink.
                data: outer,
                child: Builder(
                  builder: (context) => _sheet(context, first, shown, presence),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheet(
    BuildContext context,
    String first,
    List<Colleague> shown,
    Map<String, PresenceEntry> presence,
  ) {
    final c = context.vp;
    final pickedFirst = _picked?.name.split(' ').first;
    return Column(
      children: [
        Container(
          width: 40,
          height: 5,
          margin: const EdgeInsets.fromLTRB(0, 10, 0, 6),
          decoration: BoxDecoration(
            color: c.borderStrong,
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Transfer $first to',
                    style: vpTitle(context, size: 20, line: 26),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Cancel',
                excludeSemantics: true,
                onTap: _cancel,
                child: InkWell(
                  onTap: _cancel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                    child: Text(
                      'Cancel',
                      style: VpType.body.copyWith(
                        fontSize: 14,
                        color: c.brandText,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        decoration: TextDecoration.underline,
                        decorationColor: c.brandText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: VpType.body.copyWith(color: c.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Name, extension or number',
              hintStyle: VpType.body.copyWith(color: c.textMuted),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: VpSvgIcon(VpIcon.search, size: 18, colour: c.textMuted),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 36,
              ),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(VpRadius.md),
                borderSide: BorderSide(color: c.borderStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(VpRadius.md),
                borderSide: BorderSide(color: c.focus, width: 2),
              ),
              semanticCounterText: 'Search',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final col in shown)
                _ColleagueRow(
                  colleague: col,
                  presence:
                      presence[col.extensionValue]?.presence ??
                      col.presence.presence,
                  picked: _picked?.userId == col.userId,
                  onTap: () => setState(() => _picked = col),
                ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.border)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            4 + math.max(26, MediaQuery.viewPaddingOf(context).bottom),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: VpButton(
                      label: pickedFirst == null
                          ? 'Talk first'
                          : 'Talk to $pickedFirst first',
                      kind: VpButtonKind.outline,
                      large: false,
                      height: VpSize.controlHeight,
                      onPressed: _picked == null ? null : _talkFirst,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: VpButton(
                      label: 'Send now',
                      large: false,
                      height: VpSize.controlHeight,
                      onPressed: _picked == null ? null : _sendNow,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Talk first lets you introduce the call before handing over.',
                textAlign: TextAlign.center,
                style: vpMuted(context, size: 12, line: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColleagueRow extends StatelessWidget {
  const _ColleagueRow({
    required this.colleague,
    required this.presence,
    required this.picked,
    required this.onTap,
  });
  final Colleague colleague;
  final Presence presence;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final team = colleague.team ?? colleague.role;
    final sub = [
      colleague.extensionValue,
      team,
      presenceText(presence),
    ].whereType<String>().join(' · ');
    return Semantics(
      button: true,
      selected: picked,
      label: '${colleague.name}, $sub',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: picked ? c.brandTint : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                PresenceAvatar(name: colleague.name, presence: presence),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        colleague.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VpType.bodyStrong.copyWith(color: c.text),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VpType.caption.copyWith(
                          color: c.textMuted,
                          fontWeight: FontWeight.w500,
                          fontVariations: const [FontVariation('wght', 500)],
                        ),
                      ),
                    ],
                  ),
                ),
                if (picked)
                  VpSvgIcon(VpIcon.check, size: 20, colour: c.brandText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 40 px avatar with the presence dot: green free (status-ok), orange on a
/// call (brand), red do not disturb (status-bad), grey away or offline
/// (border-strong). Nearest tokens to the artboard's dot colours.
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({super.key, required this.name, required this.presence});
  final String name;
  final Presence presence;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final dot = switch (presenceLook(presence)) {
      PresenceLook.free => c.statusOk,
      PresenceLook.onCall => c.brand,
      PresenceLook.dnd => c.statusBad,
      PresenceLook.away => c.borderStrong,
    };
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Text(
              initialsOf(name),
              textScaler: TextScaler.noScaling,
              style: VpType.body.copyWith(
                fontSize: 14,
                height: 1,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                color: c.text,
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: c.canvas, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
