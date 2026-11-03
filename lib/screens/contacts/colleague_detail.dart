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
import '../../widgets/vp_list.dart';
import '../recents/recent_detail.dart';

/// The colleague picked in Contacts (by user id): beside the list from
/// about 680 dp ([listDetailMinWidth]; FoldContacts), else on its own page.
/// Kept across fold and unfold; until one is picked, the wide layout shows
/// the first colleague other than you and the phone layout shows the list.
final pickedColleagueProvider = NotifierProvider<PickedNotifier, String?>(
  PickedNotifier.new,
);

/// The team member picked on Teams (by user id). Each tab has its own pick
/// (TJ, 3 Nov): the pane shows the current tab's.
final pickedTeamMemberProvider = NotifierProvider<PickedNotifier, String?>(
  PickedNotifier.new,
);

/// The contact picked on Phone contacts: a phone contact ([phonePickKey]) or
/// a shared phonebook entry ([sharedPickKey]), shown as a colleague is.
final pickedPhoneContactProvider = NotifierProvider<PickedNotifier, String?>(
  PickedNotifier.new,
);

String phonePickKey(PhoneContact p) => 'phone:${p.key}';
String sharedPickKey(SharedContact s) => 'shared:${s.id}';

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

/// "mobile" as a field's label: "Mobile". Labels that start with a
/// capital already ("iPhone", "ISDN") stay as they are.
String labelTitle(String label) {
  if (label.isEmpty) return label;
  final a = label[0];
  final b = label.length > 1 ? label[1] : '';
  if (a.toLowerCase() != a || (b.toUpperCase() == b && b.toLowerCase() != b)) {
    return label;
  }
  return a.toUpperCase() + label.substring(1);
}

/// "Main" as a button's word: "Call main". Only the phone's standard words
/// ([isStandardPhoneLabel]) are lowered, and not those with another capital
/// ("ISDN", "Apple Watch", "iPhone"); a label the person typed ("Rowan's
/// clinic") stays exactly as written.
String labelWord(String label) {
  if (label.isEmpty || !isStandardPhoneLabel(label)) return label;
  final rest = label.substring(1);
  if (rest.toLowerCase() != rest) return label;
  return label[0].toLowerCase() + rest;
}

/// FoldContacts' detail: the colleague with presence, Call (extension) and
/// Call mobile, their contact details and teams, and the calls with them.
/// Beside the list when [wide]; on the phone, the same detail as its own
/// page with Back ([onBack]).
///
/// What the app can't show yet, never as a dead button:
/// - "Send to voicemail" (A5: no direct-to-voicemail call in the contract);
/// - an email address (not in the directory's colleague).
class ColleagueDetail extends ConsumerWidget {
  const ColleagueDetail({
    super.key,
    required this.colleague,
    this.wide = false,
    this.onBack,
  });
  final Colleague colleague;
  final bool wide;
  final VoidCallback? onBack;

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

    return DetailFrame(
      wide: wide,
      backLabel: 'Back to Contacts',
      onBack: onBack,
      children: [
        _Header(name: col.name, sub: sub, presence: p),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _CallButton(
              label: 'Call ${col.extensionValue}',
              onPressed: () => dialNumber(context, ref, col.extensionValue),
            ),
            if (mobile != null)
              _CallButton(
                label: 'Call mobile',
                primary: false,
                onPressed: () => dialNumber(context, ref, mobile),
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
      ],
    );
  }
}

/// A contact from the phone's own address book, laid out as a colleague
/// (TJ, 3 Nov): the name, "On this phone", Call for the first number, and
/// every number with its label (mobile, work, home…), each one a call.
///
/// No "Calls with": that needs `GET /history?number=` with the contact's
/// number, and the address book never leaves the phone (APP12).
class PhoneContactDetail extends StatelessWidget {
  const PhoneContactDetail({
    super.key,
    required this.contact,
    this.wide = false,
    this.onBack,
  });
  final PhoneContact contact;
  final bool wide;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => _NumbersDetail(
    name: contact.name,
    sub: 'On this phone',
    numbers: [
      for (final (i, n) in contact.numbers.indexed) (contact.labelAt(i), n),
    ],
    wide: wide,
    onBack: onBack,
  );
}

/// An entry in the tenant's shared phonebook ("In the apps"; TJ, 3 Nov), as
/// a phone contact is: the name, the company, and each number with its
/// label, each one a call.
class SharedContactDetail extends StatelessWidget {
  const SharedContactDetail({
    super.key,
    required this.contact,
    this.wide = false,
    this.onBack,
  });
  final SharedContact contact;
  final bool wide;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final s = contact;
    final company = s.company;
    return _NumbersDetail(
      name: s.name,
      sub: [
        if (company != null && company.isNotEmpty && company != s.name) company,
        'Shared phonebook',
      ].join(' · '),
      numbers: [
        for (final n in s.numbers)
          (n.label.trim().isEmpty ? 'phone' : n.label, n.number),
      ],
      wide: wide,
      onBack: onBack,
    );
  }
}

/// A phone contact's or shared phonebook entry's detail: the header, Call
/// for the first number, and the numbers card. Every call goes the one way
/// ([dialNumber]), so an emergency number opens AppEmergency.
class _NumbersDetail extends ConsumerWidget {
  const _NumbersDetail({
    required this.name,
    required this.sub,
    required this.numbers,
    required this.wide,
    required this.onBack,
  });
  final String name;
  final String sub;

  /// (label, number), in the contact's order.
  final List<(String, String)> numbers;
  final bool wide;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = numbers.firstOrNull;
    return DetailFrame(
      wide: wide,
      backLabel: 'Back to Contacts',
      onBack: onBack,
      children: [
        _Header(name: name, sub: sub),
        if (first != null)
          Wrap(
            children: [
              _CallButton(
                // A number with no label is just "Call".
                label: first.$1.toLowerCase() == 'phone'
                    ? 'Call'
                    : 'Call ${labelWord(first.$1)}',
                onPressed: () => dialNumber(context, ref, first.$2),
              ),
            ],
          ),
        DetailCard(
          title: numbers.length == 1 ? 'Number' : 'Numbers',
          children: [
            for (final (i, (label, n)) in numbers.indexed)
              _NumberLine(
                label: labelTitle(label),
                number: formatAuNumber(n),
                onCall: () => dialNumber(context, ref, n),
                last: i == numbers.length - 1,
              ),
          ],
        ),
      ],
    );
  }
}

/// The avatar, the name (a heading) and the line under it.
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.sub, this.presence});
  final String name;
  final String sub;
  final PresenceEntry? presence;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Row(
      children: [
        ExcludeSemantics(
          child: _BigAvatar(name: name, presence: presence),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: VpWordSafeText(
                  name,
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
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.label,
    required this.onPressed,
    this.primary = true,
  });
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => IntrinsicWidth(
    child: VpButton(
      label: label,
      icon: primary ? VpIcon.phone : null,
      kind: primary ? VpButtonKind.primary : VpButtonKind.outline,
      large: false,
      height: VpSize.controlHeight + 8,
      onPressed: onPressed,
    ),
  );
}

/// A 60 px avatar on the surface with a border (FoldContacts), and the
/// presence dot for a colleague.
class _BigAvatar extends StatelessWidget {
  const _BigAvatar({required this.name, this.presence});
  final String name;
  final PresenceEntry? presence;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final p = presence;
    final dot = p == null
        ? null
        : switch (presenceLook(p.presence)) {
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
          if (dot != null)
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
  const _Field(this.label, this.value, {this.trailing});
  final String label;
  final String value;

  /// A phone contact's number: its call button, at the end of the row.
  final Widget? trailing;

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
    final kv = large
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [l, v])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              l,
              const SizedBox(width: 12),
              Expanded(child: v),
            ],
          );
    final t = trailing;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t == null ? 6 : 0),
        child: t == null
            ? kv
            : Row(
                children: [
                  Expanded(child: kv),
                  const SizedBox(width: 8),
                  t,
                ],
              ),
      ),
    );
  }
}

/// One of a phone contact's numbers: "Mobile 0491 570 156" as a [_Field],
/// and its call button; tapping the row calls it too.
class _NumberLine extends StatelessWidget {
  const _NumberLine({
    required this.label,
    required this.number,
    required this.onCall,
    this.last = false,
  });
  final String label;
  final String number;
  final VoidCallback onCall;

  /// The card's last row: no rule under it.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Semantics(
      container: true,
      button: true,
      label: 'Call $label, $number',
      excludeSemantics: true,
      onTap: onCall,
      child: InkWell(
        onTap: onCall,
        child: Container(
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: c.border)),
          ),
          child: _Field(
            label,
            number,
            trailing: VpRoundIconButton(
              icon: VpIcon.phone,
              label: 'Call $label',
              onPressed: onCall,
            ),
          ),
        ),
      ),
    );
  }
}
