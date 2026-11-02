import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../features/recents/recents_data.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import 'call_widgets.dart';
import 'in_call_screen.dart' show audioRouteName;
import 'incoming_screen.dart' show RepeatCallerPill;

/// "Not shown yet": FoldInCall draws something the platform doesn't send
/// yet. Said plainly, never a dead button.
const notShownYet = 'Not shown yet';

/// FoldInCall's side panel beside the call, on ink in both themes: the
/// repeat caller tag and who answered last (from the incoming call's push,
/// when it carried them), about the caller, their voicemail, call quality,
/// and the note on folding. Only what the app has: call quality per call
/// (A8) and calls this month (no number filter on `GET /history` yet)
/// read [notShownYet].
class CallDetailsPanel extends ConsumerWidget {
  const CallDetailsPanel({
    super.key,
    required this.call,
    required this.localName,
    required this.audio,
  });

  final CallSnapshot call;

  /// The caller's best name ([callerName]), or null for a bare number.
  final String? localName;
  final AudioState? audio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final number = call.remoteNumber;
    final private = isPrivateNumber(number);
    final digits = nationalDigits(number);
    final info = call.incoming;
    final repeat = info?.repeatCount ?? 0;
    final lastBy = info?.lastAnsweredBy;
    final lastAt = info?.lastAnsweredAt;

    // Who they are, in the app's order: a colleague, then the phonebook.
    final colleague = private
        ? null
        : (ref.watch(colleaguesProvider).value ?? const <Colleague>[])
              .where(
                (c) =>
                    c.extensionValue == number ||
                    (c.mobile != null && nationalDigits(c.mobile!) == digits),
              )
              .firstOrNull;
    final contact = private || colleague != null
        ? null
        : (ref.watch(sharedContactsProvider).value ?? const <SharedContact>[])
              .where(
                (s) => s.numbers.any((n) => nationalDigits(n.number) == digits),
              )
              .firstOrNull;
    final name = localName;
    // "About Jordan" for a person; a company or a bare number in full.
    final person =
        colleague != null ||
        (contact != null &&
            contact.company != null &&
            contact.company != contact.name);
    final short = name == null
        ? 'this caller'
        : person
        ? name.split(' ').first
        : name;

    final history = private
        ? const <HistoryEntry>[]
        : [
            for (final h
                in ref.watch(historyProvider(RecentsFilter.all)).value?.items ??
                    const <HistoryEntry>[])
              if (nationalDigits(h.number) == digits) h,
          ];
    final last = history.firstOrNull;
    final waiting = private
        ? 0
        : (ref.watch(voicemailMessagesProvider(null)).value ??
                  const <VoicemailMessage>[])
              .where((m) => !m.heard && nationalDigits(m.number) == digits)
              .length;

    final about = <(String, String)>[
      if (colleague != null)
        (
          'Colleague',
          [
            colleague.team,
            'ext ${colleague.extensionValue}',
          ].whereType<String>().join(', '),
        )
      else if (contact != null)
        ('Phonebook', contact.company ?? contact.name),
      if (!private) ('Calls this month', notShownYet),
      if (last != null) ('Last call', _lastCall(last, now)),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: VpCallColours.tagBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            18,
            24,
            18 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (box.maxHeight - 36).clamp(0, double.infinity),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (repeat >= 2 || lastBy != null) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (repeat >= 2)
                          RepeatCallerPill(
                            text: '${ordinal(repeat)} call this week',
                            dark: true,
                          ),
                        if (lastBy != null)
                          Text(
                            lastAt == null
                                ? 'Last answered by $lastBy'
                                : 'Last answered by $lastBy, '
                                      '${whenShort(lastAt, now)}',
                            style: callText(13, colour: VpCallColours.muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (about.isNotEmpty) ...[
                    _Card(
                      title: 'About $short',
                      children: [
                        for (final (k, v) in about) _Row(label: k, value: v),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!private) ...[
                    _Card(
                      title: 'Voicemail',
                      children: [
                        Text(
                          waiting == 0
                              ? 'None waiting from $short'
                              : '$waiting waiting from $short',
                          style: callText(
                            13,
                            colour: VpCallColours.soft,
                            height: 19 / 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  _Card(
                    title: 'Call quality',
                    children: [
                      const _Row(label: 'Now', value: notShownYet),
                      _Row(
                        label: 'Audio',
                        value: audioRouteName(
                          audio?.route ?? AudioRoute.earpiece,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(height: 14),
                  Text(
                    'Fold the phone and the call carries on on the cover '
                    'screen, in the normal layout.',
                    style: callText(
                      12,
                      colour: VpCallColours.muted,
                      height: 17 / 12,
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

  /// "Today 9:15 am, 2:40".
  static String _lastCall(HistoryEntry h, DateTime now) {
    final a = h.at.toLocal(), n = now.toLocal();
    final days = DateTime(
      n.year,
      n.month,
      n.day,
    ).difference(DateTime(a.year, a.month, a.day)).inDays;
    final when = switch (days) {
      <= 0 => 'Today ${clockTime(a)}',
      1 => 'Yesterday ${clockTime(a)}',
      _ => recentsWhen(h.at, now),
    };
    final d = h.durationSeconds;
    return d == null || d == 0 ? when : '$when, ${minutesSeconds(d)}';
  }
}

/// A 16-radius card on charcoal, 16 18 padding, a 14 px title.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    decoration: BoxDecoration(
      color: VpPalette.charcoal850,
      border: Border.all(color: VpCallColours.tagBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: callText(14, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

/// `.kv`: the label muted on the left, the value bold on the right, one
/// line each.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: callText(14, colour: VpCallColours.muted),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: callText(14, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}
