import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../emergency/emergency.dart';
import '../../features/recents/recents_data.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../shell/list_detail.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../recents/recent_detail.dart';

/// The colleague picked in Contacts (by user id), shown beside the list from
/// about 680 dp ([listDetailMinWidth]; FoldContacts). Kept across fold and
/// unfold; until one is picked, the first colleague other than you shows.
final pickedColleagueProvider = NotifierProvider<PickedNotifier, String?>(
  PickedNotifier.new,
);

/// "Ava Nguyen called you, 4:02", "You called Priya, 1:37" (FoldContacts);
/// anything else as Recents says it.
String colleagueCallLine(HistoryEntry h, String first) {
  final d = h.durationSeconds;
  final dur = d == null || d == 0 ? '' : ', ${minutesSeconds(d)}';
  if (h.outcome == HistoryEntryOutcome.answered) {
    return h.direction == HistoryEntryDirection.outgoing
        ? 'You called $first$dur'
        : '$first called you$dur';
  }
  return callWithLine(h);
}

/// FoldContacts' detail: the colleague with presence, Call (extension) and
/// Call mobile, their contact details and teams, and the calls with them.
///
/// What the app can't show yet, never as a dead button:
/// - "Send to voicemail" (A5: no direct-to-voicemail call in the contract);
/// - an email address (not in the directory's colleague).
class ColleagueDetail extends ConsumerWidget {
  const ColleagueDetail({super.key, required this.colleague});
  final Colleague colleague;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final col = colleague;
    final p = ref.watch(presenceProvider)[col.extensionValue] ?? col.presence;
    final now = ref.watch(clockProvider)();
    final first = col.name.split(' ').first;
    final status = switch (p.presence) {
      Presence.available => 'Free',
      Presence.onCall when p.since != null =>
        'On a call · ${minutesSeconds(now.difference(p.since!).inSeconds)}',
      Presence.dnd when p.dndUntil != null =>
        'Do not disturb until ${clockTime(p.dndUntil!.toLocal())}',
      _ => presenceText(p.presence),
    };
    final sub = [
      col.role,
      'ext ${col.extensionValue}',
      status,
    ].whereType<String>().join(' · ');
    final teams = [
      for (final t in ref.watch(teamsProvider).value ?? const <Team>[])
        if (t.members.contains(col.userId)) t.name,
    ];
    final mobile = col.mobile;
    final calls = [
      ...?ref.watch(callsWithProvider(col.extensionValue)).value,
      if (mobile != null) ...?ref.watch(callsWithProvider(mobile)).value,
    ]..sort((a, b) => b.at.compareTo(a.at));

    final children = <Widget>[
      Row(
        children: [
          ExcludeSemantics(
            child: _BigAvatar(name: col.name, presence: p),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: VpWordSafeText(
                    col.name,
                    maxLines: 2,
                    style: vpTitle(context, size: 24, line: 30),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: VpType.body.copyWith(fontSize: 14, color: c.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          IntrinsicWidth(
            child: VpButton(
              label: 'Call ${col.extensionValue}',
              icon: VpIcon.phone,
              large: false,
              height: VpSize.controlHeight + 8,
              onPressed: () => dialNumber(context, ref, col.extensionValue),
            ),
          ),
          if (mobile != null)
            IntrinsicWidth(
              child: VpButton(
                label: 'Call mobile',
                kind: VpButtonKind.outline,
                large: false,
                height: VpSize.controlHeight + 8,
                onPressed: () => dialNumber(context, ref, mobile),
              ),
            ),
        ],
      ),
      // GAP(A5): "Send to voicemail" goes here once the contract can call a
      // colleague's voicemail without ringing them.
      DetailCard(
        title: 'Contact',
        children: [
          _Field('Extension', col.extensionValue),
          if (mobile != null) _Field('Mobile', formatAuNumber(mobile)),
          if (teams.isNotEmpty) _Field('Teams', teams.join(', ')),
        ],
      ),
      DetailCard(
        title: 'Calls with $first',
        children: [
          if (calls.isEmpty)
            Text(
              'No calls with $first yet.',
              style: VpType.body.copyWith(fontSize: 13, color: c.textMuted),
            ),
          for (final x in calls)
            DetailCallLine(
              missed: historyIsMissed(x),
              text: colleagueCallLine(x, first),
              when: callWhen(x.at, now),
            ),
        ],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      children: [
        for (final (i, w) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 18),
          w,
        ],
      ],
    );
  }
}

/// A 60 px avatar on the surface with a border (FoldContacts), and the
/// presence dot.
class _BigAvatar extends StatelessWidget {
  const _BigAvatar({required this.name, required this.presence});
  final String name;
  final PresenceEntry presence;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final dot = switch (presenceLook(presence.presence)) {
      PresenceLook.free => c.statusOk,
      PresenceLook.onCall => c.brand,
      PresenceLook.dnd => c.statusBad,
      PresenceLook.away => c.borderStrong,
    };
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: c.border),
            ),
            child: Text(
              initialsOf(name),
              textScaler: TextScaler.noScaling,
              style: VpType.body.copyWith(
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                color: c.text,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: c.canvas, width: 3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.kv`: the label muted on the left, the value bold on the right; at
/// large text the value goes under its label.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    final l = Text(
      label,
      style: VpType.body.copyWith(fontSize: 14, color: c.textMuted),
    );
    final v = Text(
      value,
      textAlign: large ? TextAlign.start : TextAlign.end,
      style: VpType.body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
        color: c.text,
      ),
    );
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [l, v],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  l,
                  const SizedBox(width: 12),
                  Expanded(child: v),
                ],
              ),
      ),
    );
  }
}
