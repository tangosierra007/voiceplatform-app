import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../emergency/emergency.dart';
import '../../features/recents/recents_data.dart';
import '../../features/recents/recents_format.dart';
import '../../features/recents/voicemail_actions.dart';
import '../../net/api.dart';
import '../../shell/shell_status.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';
import '../../widgets/vp_wide.dart';
import '../../shell/list_detail.dart';
import '../../shell/layout.dart';
import 'recent_detail.dart';
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
    _list?.dispose();
    super.dispose();
  }

  /// The list's place, kept across fold and unfold: the phone's list and
  /// the one beside the detail are different lists, so each new one starts
  /// where the last one was.
  double _listOffset = 0;
  ScrollController? _list;
  bool? _listWide;

  ScrollController _listController({required bool wide}) {
    if (_list == null || _listWide != wide) {
      final old = _list;
      final next = ScrollController(initialScrollOffset: _listOffset);
      next.addListener(() {
        if (next.hasClients) _listOffset = next.offset;
      });
      _list = next;
      _listWide = wide;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    return _list!;
  }

  HistoryEntry? _find(String id, RecentsFilter filter) {
    for (final f in {filter, RecentsFilter.all}) {
      final hit = (ref.read(historyProvider(f)).value?.items ?? const [])
          .where((h) => h.id == id)
          .firstOrNull;
      if (hit != null) return hit;
    }
    return null;
  }

  void _pick(String? id) => ref.read(pickedRecentProvider.notifier).pick(id);

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(recentsFilterProvider);
    ref.watch(historyProvider(filter));
    ref.watch(historyProvider(RecentsFilter.all));
    final picked = ref.watch(pickedRecentProvider);
    final entry = picked == null ? null : _find(picked, filter);
    if (isListDetailLayout(context)) return _wide(context, filter, entry);
    if (entry != null) {
      // The call's own page on the phone; Back returns to the list.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _pick(null);
        },
        child: SafeArea(
          bottom: false,
          child: RecentDetail(
            key: ValueKey(entry.id),
            entry: entry,
            onBack: () => _pick(null),
          ),
        ),
      );
    }
    return _phone(context, filter);
  }

  Widget _seg(RecentsFilter filter, {required bool wide}) {
    final counts = ref.watch(historyProvider(RecentsFilter.all)).value?.counts;
    String withCount(String label, int? n) =>
        n == null || n == 0 ? label : '$label $n';
    return VpSeg<RecentsFilter>(
      label: 'Show',
      options: [
        (RecentsFilter.all, 'All'),
        (RecentsFilter.missed, withCount('Missed', counts?.missed)),
        (
          RecentsFilter.voicemail,
          withCount(
            'Voicemail',
            counts == null
                ? null
                : withPending(
                    counts.voicemail,
                    ref
                        .watch(voicemailPendingProvider)
                        .total(VoicemailCount.history),
                  ),
          ),
        ),
        // "Mine only" in both layouts (TJ, 2 Nov; FoldRecents' "Mine" is
        // corrected).
        (RecentsFilter.mine, 'Mine only'),
      ],
      value: filter,
      onChanged: (f) {
        if (f != RecentsFilter.voicemail) {
          unawaited(_player.stop());
        }
        ref.read(recentsFilterProvider.notifier).set(f);
      },
    );
  }

  Widget? _greeting(BuildContext context, RecentsFilter filter) =>
      filter == RecentsFilter.voicemail
      ? VpLink(
          'Greeting',
          onTap: () => context.push(RecentsScreen.greetingPath),
        )
      : null;

  /// FoldRecents: the calls (360 dp) and the one picked beside them; until
  /// the person picks one, the newest in the list.
  Widget _wide(
    BuildContext context,
    RecentsFilter filter,
    HistoryEntry? picked,
  ) {
    final first =
        (ref.watch(historyProvider(filter)).value?.items ??
                const <HistoryEntry>[])
            .firstOrNull ??
        (ref.watch(historyProvider(RecentsFilter.all)).value?.items ??
                const <HistoryEntry>[])
            .firstOrNull;
    final shown = picked ?? first;
    return SafeArea(
      bottom: false,
      child: ListDetailLayout(
        list: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WideListHeader(
              title: 'Recents',
              trailing: _greeting(context, filter),
              children: [_seg(filter, wide: true)],
            ),
            Expanded(
              child: filter == RecentsFilter.voicemail
                  ? const VoicemailView()
                  : _HistoryList(
                      filter: filter,
                      controller: _listController(wide: true),
                      wide: true,
                      shownId: shown?.id,
                      onPick: _pick,
                    ),
            ),
          ],
        ),
        detail: shown == null
            ? const SizedBox.shrink()
            : RecentDetail(key: ValueKey(shown.id), entry: shown, wide: true),
      ),
    );
  }

  Widget _phone(BuildContext context, RecentsFilter filter) => SafeArea(
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
                // The same height with or without the link, so the filters
                // don't move between All and Voicemail.
                trailing:
                    _greeting(context, filter) ?? const SizedBox(height: 48),
              ),
              const SizedBox(height: 12),
              _seg(filter, wide: false),
            ],
          ),
        ),
        Expanded(
          child: filter == RecentsFilter.voicemail
              ? const VoicemailView()
              : _HistoryList(
                  filter: filter,
                  controller: _listController(wide: false),
                ),
        ),
      ],
    ),
  );
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({
    required this.filter,
    required this.controller,
    this.wide = false,
    this.shownId,
    this.onPick,
  });
  final RecentsFilter filter;
  final ScrollController controller;

  /// FoldRecents' compact rows; a tap shows the call beside the list.
  final bool wide;
  final String? shownId;
  final ValueChanged<String>? onPick;

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
        controller: controller,
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
          else if (wide)
            for (final h in items)
              _WideHistoryRow(
                entry: h,
                title: historyTitle(h, matcher),
                when: recentsWhen(h.at, now),
                selected: h.id == shownId,
                onTap: () => onPick?.call(h.id),
              )
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

  /// Opens the call's own page (RecentDetail); unfolded, it shows beside
  /// the list.
  void _details(BuildContext context, WidgetRef ref) =>
      ref.read(pickedRecentProvider.notifier).pick(entry.id);
}

/// FoldRecents' `.lrow`: a 34 px icon tile, the caller (in the alert colour
/// when missed), what happened, the time. A tap shows it beside the list;
/// Call back is in the detail.
class _WideHistoryRow extends StatelessWidget {
  const _WideHistoryRow({
    required this.entry,
    required this.title,
    required this.when,
    required this.selected,
    required this.onTap,
  });
  final HistoryEntry entry;
  final String title;
  final String when;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final missed = historyIsMissed(entry);
    final sub = historySubtitle(entry);
    final (icon, iconColour) = switch (entry) {
      _ when missed => (VpIcon.missedCall, c.statusBad),
      HistoryEntry(outcome: HistoryEntryOutcome.answeredElsewhere) => (
        VpIcon.transfer,
        c.textMuted,
      ),
      HistoryEntry(direction: HistoryEntryDirection.outgoing) => (
        VpIcon.outgoingCall,
        c.textMuted,
      ),
      _ => (VpIcon.incomingCall, c.textMuted),
    };
    // Large text in the narrow list (280 dp at 680): the time goes under
    // the caller, and each line may take two, so the name still reads.
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    final lines = large ? 2 : 1;
    return WideListRow(
      selected: selected,
      onTap: onTap,
      semanticLabel: '$title, $sub, $when. Details',
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
          ),
          child: VpSvgIcon(icon, size: 18, colour: iconColour),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: lines,
                overflow: TextOverflow.ellipsis,
                style: VpType.body.copyWith(
                  fontSize: 15,
                  height: 22 / 15,
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  color: missed ? c.statusBad : c.text,
                ),
              ),
              Text(
                sub,
                maxLines: lines,
                overflow: TextOverflow.ellipsis,
                style: VpType.caption.copyWith(color: c.textMuted),
              ),
              if (large)
                Text(
                  when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VpType.caption.copyWith(color: c.textMuted),
                ),
            ],
          ),
        ),
        if (!large)
          Text(when, style: VpType.caption.copyWith(color: c.textMuted)),
      ],
    );
  }
}
