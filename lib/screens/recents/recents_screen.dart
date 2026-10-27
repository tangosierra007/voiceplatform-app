import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../emergency/emergency.dart';
import '../../features/recents/recents_data.dart';
import '../../features/recents/recents_format.dart';
import '../../features/recents/voicemail_actions.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';
import 'voicemail_view.dart';

/// AppRecents: the call history with All, Missed, Voicemail and Mine only;
/// Voicemail shows the boxes and the player in place (AppVoicemail).
class RecentsScreen extends ConsumerStatefulWidget {
  const RecentsScreen({super.key});

  static const greetingPath = '/recents/greeting';

  @override
  ConsumerState<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends ConsumerState<RecentsScreen> {
  late final VoicemailPlayerNotifier _player;

  @override
  void initState() {
    super.initState();
    _player = ref.read(voicemailPlayerProvider.notifier);
    // Opening Recents clears the missed-call part of the badge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(markHistorySeenProvider)());
    });
  }

  @override
  void dispose() {
    unawaited(_player.stop().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(recentsFilterProvider);
    final counts = ref.watch(historyProvider(RecentsFilter.all)).value?.counts;
    String withCount(String label, int? n) =>
        n == null || n == 0 ? label : '$label $n';
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VpPageTitle(
                  'Recents',
                  // The same height with or without the link, so the
                  // filters don't move between All and Voicemail.
                  trailing: filter == RecentsFilter.voicemail
                      ? VpLink(
                          'Greeting',
                          onTap: () => context.push(RecentsScreen.greetingPath),
                        )
                      : const SizedBox(height: 48),
                ),
                const SizedBox(height: 12),
                VpSeg<RecentsFilter>(
                  label: 'Show',
                  options: [
                    (RecentsFilter.all, 'All'),
                    (RecentsFilter.missed, withCount('Missed', counts?.missed)),
                    (
                      RecentsFilter.voicemail,
                      withCount('Voicemail', counts?.voicemail),
                    ),
                    (RecentsFilter.mine, 'Mine only'),
                  ],
                  value: filter,
                  onChanged: (f) {
                    if (f != RecentsFilter.voicemail) {
                      unawaited(_player.stop());
                    }
                    ref.read(recentsFilterProvider.notifier).set(f);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: filter == RecentsFilter.voicemail
                ? const VoicemailView()
                : _HistoryList(filter: filter),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.filter});
  final RecentsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(historyProvider(filter));
    final matcher = ref.watch(contactMatcherProvider);
    final now = ref.watch(clockProvider)();
    Future<void> refresh() async {
      ref.invalidate(historyProvider(filter));
      try {
        await ref.read(historyProvider(filter).future);
      } catch (_) {}
    }

    final items = page.value?.items;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (items == null && page.hasError)
            const VpEmpty("Recents didn't load. Pull down to try again.")
          else if (items == null)
            const SizedBox.shrink()
          else if (items.isEmpty)
            VpEmpty(switch (filter) {
              RecentsFilter.missed => 'No missed calls.',
              RecentsFilter.mine => 'No calls to or from you yet.',
              _ => 'No calls yet.',
            })
          else
            for (final h in items)
              _HistoryRow(
                entry: h,
                title: historyTitle(h, matcher),
                when: recentsWhen(h.at, now),
              ),
        ],
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({
    required this.entry,
    required this.title,
    required this.when,
  });
  final HistoryEntry entry;
  final String title;
  final String when;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final missed = historyIsMissed(entry);
    final private = isPrivateNumber(entry.number);
    final sub = historySubtitle(entry);
    final (icon, iconColour) = switch (entry) {
      _ when missed => (VpIcon.missedCall, c.statusBad),
      HistoryEntry(outcome: HistoryEntryOutcome.answeredElsewhere) => (
        VpIcon.transfer,
        c.textDisabled,
      ),
      HistoryEntry(direction: HistoryEntryDirection.outgoing) => (
        VpIcon.outgoingCall,
        c.textMuted,
      ),
      _ => (VpIcon.incomingCall, c.textMuted),
    };
    return Semantics(
      container: true,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: !private,
                  label: private
                      ? '$title, $sub, $when'
                      : 'Call back $title, $sub, $when',
                  excludeSemantics: true,
                  onTap: private ? null : () => _callBack(context, ref),
                  child: InkWell(
                    // Tapping a row calls back; Private has no number to call.
                    onTap: private ? null : () => _callBack(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 0, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c.surfaceRaised,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: VpSvgIcon(
                              icon,
                              size: 18,
                              colour: iconColour,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: VpRowText(
                              title: title,
                              subtitle: sub,
                              titleColour: missed ? c.statusBad : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            when,
                            style: VpType.caption.copyWith(
                              color: c.textMuted,
                              fontWeight: FontWeight.w500,
                              fontVariations: const [
                                FontVariation('wght', 500),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Details for $title',
                excludeSemantics: true,
                onTap: () => _details(context, ref),
                child: InkWell(
                  onTap: () => _details(context, ref),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: VpSvgIcon(
                        VpIcon.info,
                        size: 18,
                        colour: c.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callBack(BuildContext context, WidgetRef ref) =>
      dialNumber(context, ref, entry.number);

  Future<void> _details(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: context.vp.surface,
        builder: (sheet) => _DetailsSheet(
          entry: entry,
          title: title,
          onCallBack: () => _callBack(context, ref),
        ),
      );
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `Tuesday 27 October, 11:04 am`.
String _fullWhen(DateTime at) {
  final a = at.toLocal();
  return '${_weekdays[a.weekday - 1]} ${a.day} ${_monthNames[a.month - 1]}, '
      '${clockTime(a)}';
}

class _DetailsSheet extends ConsumerWidget {
  const _DetailsSheet({
    required this.entry,
    required this.title,
    required this.onCallBack,
  });
  final HistoryEntry entry;
  final String title;
  final VoidCallback onCallBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final private = isPrivateNumber(entry.number);
    final number = formatAuNumber(entry.number);
    final lines = [
      if (!private && number != title) number,
      historySubtitle(entry),
      _fullWhen(entry.at),
      if (entry.line != null && entry.line!.isNotEmpty)
        'To the ${entry.line} line',
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: vpTitle(context, size: 20, line: 26)),
            ),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l,
                  style: VpType.body.copyWith(fontSize: 14, color: c.textMuted),
                ),
              ),
            const SizedBox(height: 12),
            if (!private)
              VpButton(
                label: 'Call back',
                icon: VpIcon.phone,
                large: false,
                height: VpSize.controlHeight,
                onPressed: () {
                  Navigator.of(context).pop();
                  onCallBack();
                },
              ),
            if (entry.voicemailId != null) ...[
              const SizedBox(height: 8),
              VpButton(
                label: 'Play voicemail',
                kind: VpButtonKind.outline,
                icon: VpIcon.voicemail,
                large: false,
                height: VpSize.controlHeight,
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(voicemailBoxProvider.notifier).set(null);
                  ref
                      .read(openVoicemailProvider.notifier)
                      .set(entry.voicemailId);
                  ref
                      .read(recentsFilterProvider.notifier)
                      .set(RecentsFilter.voicemail);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
