import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../emergency/emergency.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../features/recents/recents_data.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../keypad/keypad_screen.dart';
import 'voicemail_view.dart';

/// `Today 11:04 am`, `Yesterday 9:40 am`, `Tue 2:15 pm`, `14 Oct`.
String callWhen(DateTime at, DateTime now) {
  final a = at.toLocal(), n = now.toLocal();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(a.year, a.month, a.day)).inDays;
  if (days <= 0) return 'Today ${clockTime(a)}';
  if (days == 1) return 'Yesterday ${clockTime(a)}';
  return whenShort(at, now);
}

/// One call in "Recent calls with …": `Missed, left voicemail`,
/// `Answered by Ava, 3:05`, `Answered by Mia on her desk phone`,
/// `You called, 1:37`.
String callWithLine(HistoryEntry h, {String? myFirstName}) {
  final d = h.durationSeconds;
  final dur = d == null ? '' : ', ${minutesSeconds(d)}';
  final out = h.direction == HistoryEntryDirection.outgoing;
  return switch (h.outcome) {
    HistoryEntryOutcome.voicemail => 'Missed, left voicemail',
    HistoryEntryOutcome.missed => out ? 'You called, no answer' : 'Missed',
    HistoryEntryOutcome.answeredElsewhere =>
      h.answeredBy == null || h.answeredBy!.isEmpty
          ? 'Answered elsewhere'
          : 'Answered by ${h.answeredBy}',
    HistoryEntryOutcome.answered =>
      out
          ? 'You called$dur'
          : myFirstName == null
          ? 'Answered$dur'
          : 'Answered by $myFirstName$dur',
    _ => historySubtitle(h),
  };
}

/// "Last answered by Ava Nguyen, Tue 2:15 pm": the latest answered call in
/// [calls] (newest first); null when none of them was answered.
String? lastAnsweredLine(
  List<HistoryEntry> calls,
  DateTime now, {
  String? myName,
}) {
  for (final h in calls) {
    if (h.direction != HistoryEntryDirection.incoming) continue;
    final who = switch (h.outcome) {
      HistoryEntryOutcome.answered => myName,
      HistoryEntryOutcome.answeredElsewhere => h.answeredBy,
      _ => null,
    };
    if (who == null || who.isEmpty) {
      if (h.outcome == HistoryEntryOutcome.answered ||
          h.outcome == HistoryEntryOutcome.answeredElsewhere) {
        return 'Last answered ${callWhen(h.at, now)}';
      }
      continue;
    }
    return 'Last answered by $who, ${callWhen(h.at, now)}';
  }
  return null;
}

/// A call's detail: the caller, Call back with the caller ID, the voicemail
/// they left, and the other calls with that number in Recents.
///
/// [wide] lays it out as FoldRecents' pane (padding 22 28, 18 apart);
/// otherwise as its own page on the phone, under a Back row.
///
/// Contract gaps, shown nowhere rather than made up (see the PR):
/// - the repeat caller tag ("2nd call today", B27) has no field yet;
/// - voicemail transcripts come later (APP_DESIGN_SCOPE);
/// - "calls with that number" can only be the calls Recents has loaded:
///   `/history` has no number filter, so the card says "Recent calls".
class RecentDetail extends ConsumerWidget {
  const RecentDetail({
    super.key,
    required this.entry,
    this.wide = false,
    this.onBack,
  });

  final HistoryEntry entry;
  final bool wide;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final matcher = ref.watch(contactMatcherProvider);
    final shared = ref.watch(sharedContactsProvider).value ?? const [];
    final colleagues = ref.watch(colleaguesProvider).value ?? const [];
    final me = ref.watch(meProvider).value;
    final now = ref.watch(clockProvider)();
    final h = entry;
    final private = isPrivateNumber(h.number);
    final title = historyTitle(h, matcher);
    final number = private ? null : formatAuNumber(h.number);
    final digits = private ? '' : nationalDigits(h.number);
    final colleague = colleagues
        .where(
          (x) =>
              x.extensionValue == digits ||
              (x.mobile != null && nationalDigits(x.mobile!) == digits),
        )
        .firstOrNull;
    final inPhonebook = shared.any(
      (s) => s.numbers.any((n) => nationalDigits(n.number) == digits),
    );
    final sub = [
      if (number != null && number != title) number,
      if (colleague != null)
        'ext ${colleague.extensionValue}'
      else if (inPhonebook)
        'in the phonebook',
      if (h.line != null && h.line!.isNotEmpty) 'to ${h.line}',
    ].join(' · ');

    // The server's calls with this number; while they load, the ones
    // Recents has.
    final all = ref.watch(historyProvider(RecentsFilter.all)).value?.items;
    final withNumber = private
        ? null
        : ref.watch(callsWithProvider(h.number)).value;
    final calls = private
        ? <HistoryEntry>[h]
        : [
            ...withNumber ??
                [
                  for (final x in all ?? <HistoryEntry>[h])
                    if (nationalDigits(x.number) == digits) x,
                ],
          ];
    if (!calls.any((x) => x.id == h.id)) calls.insert(0, h);
    final myFirst = me?.name.split(' ').first;
    final last = lastAnsweredLine(calls, now, myName: me?.name);

    VoicemailMessage? voicemail;
    final vmId = h.voicemailId;
    if (vmId != null) {
      voicemail = (ref.watch(voicemailMessagesProvider(null)).value ?? const [])
          .where((m) => m.id == vmId)
          .firstOrNull;
    }

    final avatar = Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        border: Border.all(color: c.border),
      ),
      child: Text(
        private || title == number ? '#' : initialsOf(title),
        textScaler: TextScaler.noScaling,
        style: VpType.body.copyWith(
          fontSize: 20,
          height: 1,
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 800)],
          color: c.text,
        ),
      ),
    );

    final children = <Widget>[
      Row(
        children: [
          ExcludeSemantics(child: avatar),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: VpWordSafeText(
                    title,
                    maxLines: 2,
                    style: vpTitle(context, size: 24, line: 30),
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    style: VpType.body.copyWith(
                      fontSize: 14,
                      color: c.textMuted,
                    ),
                  ),
                ],
                // GAP(B27): the repeat caller tag ("2nd call today") goes
                // here once the contract carries it.
              ],
            ),
          ),
        ],
      ),
      if (!private)
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IntrinsicWidth(
              child: VpButton(
                label: 'Call back',
                icon: VpIcon.phone,
                large: false,
                height: VpSize.controlHeight + 8,
                onPressed: () => dialNumber(context, ref, h.number),
              ),
            ),
            const CallerIdChip(alignEnd: false),
          ],
        ),
      if (voicemail != null)
        VoicemailPlayerCard(
          showCallBack: false,
          message: voicemail,
          title: title,
          when: callWhen(voicemail.at, now),
        ),
      DetailCard(
        title: 'Recent calls with $title',
        children: [
          for (final x in calls)
            DetailCallLine(
              missed: historyIsMissed(x),
              text: callWithLine(x, myFirstName: myFirst),
              when: callWhen(x.at, now),
            ),
          if (last != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                last,
                style: VpType.caption.copyWith(color: c.textMuted),
              ),
            ),
        ],
      ),
    ];

    return DetailFrame(
      wide: wide,
      backLabel: 'Back to Recents',
      onBack: onBack,
      children: children,
    );
  }
}

/// A detail's blocks, spaced and scrolling: beside the list (wide, 28 22
/// padding, 18 apart), or as its own page on the phone with Back above
/// ([backLabel] read out) and 20 8 padding, 16 apart. Recents' call and
/// Contacts' colleague and phone contact.
class DetailFrame extends StatelessWidget {
  const DetailFrame({
    super.key,
    required this.wide,
    required this.backLabel,
    required this.onBack,
    required this.children,
  });

  final bool wide;
  final String backLabel;
  final VoidCallback? onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final list = ListView(
      padding: wide
          ? const EdgeInsets.fromLTRB(28, 22, 28, 22)
          : const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        for (final (i, w) in children.indexed) ...[
          if (i > 0) SizedBox(height: wide ? 18 : 16),
          w,
        ],
      ],
    );
    if (wide) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            label: backLabel,
            excludeSemantics: true,
            onTap: onBack,
            child: InkWell(
              onTap: onBack,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: VpSvgIcon(VpIcon.back, size: 22, colour: c.brandText),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }
}

/// `.vp-card` with padding 16 18 and a 14 px bold title (a call's or a
/// contact's detail).
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(VpRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: VpType.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                color: c.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// One call: its icon, what happened, when; 8 px above and below, a rule.
class DetailCallLine extends StatelessWidget {
  const DetailCallLine({
    super.key,
    required this.missed,
    required this.text,
    required this.when,
  });
  final bool missed;
  final String text;
  final String when;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    // Large text: when goes under what happened, rather than squeeze it.
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    final whenText = Text(
      when,
      style: VpType.body.copyWith(fontSize: 13, color: c.textMuted),
    );
    return Semantics(
      container: true,
      label: '$text, $when',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            VpSvgIcon(
              missed ? VpIcon.missedCall : VpIcon.phone,
              size: 16,
              colour: missed ? c.statusBad : c.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          style: VpType.body.copyWith(
                            fontSize: 13,
                            color: c.text,
                          ),
                        ),
                        whenText,
                      ],
                    )
                  : Text(
                      text,
                      style: VpType.body.copyWith(fontSize: 13, color: c.text),
                    ),
            ),
            if (!large) ...[const SizedBox(width: 10), whenText],
          ],
        ),
      ),
    );
  }
}
