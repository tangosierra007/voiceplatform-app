import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../features/recents/recents_data.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';
import '../../widgets/vp_wide.dart';
import '../calls/transfer_screen.dart' show PresenceAvatar;

/// Where a keypad match comes from, in the order the app names people
/// (colleague, the shared phonebook, then a recent call).
enum KeypadMatchSource {
  colleague('Colleague'),
  phonebook('Phonebook'),
  recent('Recent');

  const KeypadMatchSource(this.tag);

  /// The tag at the row's end (FoldKeypad).
  final String tag;
}

/// One row in the wide keypad's matches (FoldKeypad).
@immutable
class KeypadMatch {
  const KeypadMatch({
    required this.source,
    required this.name,
    required this.detail,
    required this.number,
    this.label,
  });

  final KeypadMatchSource source;
  final String name;

  /// The muted line: "Harbour Cafe · 0491 570 737", "302 · Free",
  /// "03 5550 1987 · missed 11:04 am".
  final String detail;

  /// What a tap puts on the keypad: digits, or an extension.
  final String number;

  /// The line under the number once it's filled ("Jordan Price, Harbour
  /// Cafe"); null when the name would only repeat the number.
  final String? label;
}

/// A number filled from a match: the [number] it put on the keypad, the
/// [label] under it, and the [query] typed before the tap, so the matches
/// stay as they were with the picked one marked (FoldKeypad).
typedef PickedMatch = ({String number, String? label, String query});

/// The match picked on the wide keypad, kept in memory so it survives fold
/// and unfold. It counts only while the keypad still holds its number: any
/// key or Delete leaves it behind. Its label covers numbers the device's
/// [ContactMatcher] doesn't know (a recent call's name).
final pickedMatchProvider = NotifierProvider<PickedMatchNotifier, PickedMatch?>(
  PickedMatchNotifier.new,
);

class PickedMatchNotifier extends Notifier<PickedMatch?> {
  @override
  PickedMatch? build() => null;
  void set(PickedMatch? m) => state = m;
}

/// "Free" on FoldKeypad's colleague rows; the Contacts wording otherwise.
String _presenceShort(Presence p) =>
    p == Presence.available ? 'Free' : presenceText(p);

String _recentKind(HistoryEntry h) {
  if (historyIsMissed(h)) return 'missed';
  return h.direction == HistoryEntryDirection.outgoing
      ? 'outgoing'
      : 'incoming';
}

String _when(DateTime at, DateTime now) {
  final w = recentsWhen(at, now);
  return w == 'Yesterday' ? 'yesterday' : w;
}

/// The matches for what's on the keypad, from colleagues (extension or
/// mobile), the shared phonebook and recent calls, matched on the device.
/// A number in several sources shows once, from the first in
/// [KeypadMatchSource] order. Numbers that start with the digits come
/// before those that only contain them; the phone's own address book is
/// left out (it has no tag on FoldKeypad), though its names still show
/// under the number.
List<KeypadMatch> keypadMatches({
  required String typed,
  required List<Colleague> colleagues,
  required Map<String, PresenceEntry> presence,
  required List<SharedContact> shared,
  required List<HistoryEntry> history,
  required ContactMatcher matcher,
  required DateTime now,
}) {
  final d = nationalDigits(typed);
  if (d.isEmpty) return const [];
  final seen = <String>{};
  final starts = <KeypadMatch>[], contains = <KeypadMatch>[];
  void add(String key, KeypadMatch m) {
    if (!seen.add(key)) return;
    (key.startsWith(d) ? starts : contains).add(m);
  }

  for (final c in colleagues) {
    final p = (presence[c.extensionValue] ?? c.presence).presence;
    final detail = '${c.extensionValue} · ${_presenceShort(p)}';
    final mobile = c.mobile == null ? null : nationalDigits(c.mobile!);
    if (c.extensionValue.contains(d)) {
      add(
        c.extensionValue,
        KeypadMatch(
          source: KeypadMatchSource.colleague,
          name: c.name,
          detail: detail,
          number: c.extensionValue,
          label: '${c.name}, ext ${c.extensionValue}',
        ),
      );
    } else if (mobile != null && mobile.contains(d)) {
      add(
        mobile,
        KeypadMatch(
          source: KeypadMatchSource.colleague,
          name: c.name,
          detail: detail,
          number: mobile,
          label: c.name,
        ),
      );
    }
  }
  for (final s in shared) {
    for (final n in s.numbers) {
      final digits = nationalDigits(n.number);
      if (!digits.contains(d)) continue;
      final company = s.company;
      add(
        digits,
        KeypadMatch(
          source: KeypadMatchSource.phonebook,
          name: s.name,
          detail: [
            if (company != null && company.isNotEmpty) company,
            formatAuNumber(n.number),
          ].join(' · '),
          number: digits,
          label: company == null || company.isEmpty
              ? s.name
              : '${s.name}, $company',
        ),
      );
    }
  }
  for (final h in history) {
    if (isPrivateNumber(h.number)) continue;
    final digits = nationalDigits(h.number);
    if (!digits.contains(d)) continue;
    final number = formatAuNumber(h.number);
    final title = historyTitle(h, matcher);
    add(
      digits,
      KeypadMatch(
        source: KeypadMatchSource.recent,
        name: title,
        // A bare number is the title already: the line says only what.
        detail: [
          if (title != number) number,
          '${_recentKind(h)} ${_when(h.at, now)}',
        ].join(' · '),
        number: digits,
        label: title == number ? null : title,
      ),
    );
  }
  return [...starts, ...contains];
}

/// The keypad's matches, live.
final keypadMatchesProvider = Provider.family<List<KeypadMatch>, String>((
  ref,
  typed,
) {
  if (nationalDigits(typed).isEmpty) return const [];
  return keypadMatches(
    typed: typed,
    colleagues: ref.watch(colleaguesProvider).value ?? const [],
    presence: ref.watch(presenceProvider),
    shared: ref.watch(sharedContactsProvider).value ?? const [],
    history:
        ref.watch(historyProvider(RecentsFilter.all)).value?.items ?? const [],
    matcher: ref.watch(contactMatcherProvider),
    now: ref.watch(clockProvider)(),
  );
});

/// The left side of the wide keypad (FoldKeypad): the matches while a
/// number is typed; with nothing typed, the colleagues free now with their
/// presence, as in Contacts (TJ, 2 Nov). A tap fills the number and the
/// name in; only the call button calls.
class KeypadMatchesPane extends ConsumerWidget {
  const KeypadMatchesPane({
    super.key,
    required this.typed,
    required this.number,
    required this.onPick,
  });

  final String typed;
  final void Function(String number, String? label) onPick;

  /// What's on the keypad; [typed] is what the matches are for.
  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    final digits = nationalDigits(typed);
    final picked = nationalDigits(number);
    final header = WideListHeader(
      title: 'Keypad',
      children: [
        Text(
          'Matches as you type, from colleagues, the phonebook and recent '
          'calls',
          style: VpType.body.copyWith(fontSize: 13, color: c.textMuted),
        ),
      ],
    );
    // Each row, given whether the pane is narrow enough to stack its tag.
    final List<Widget Function(bool stacked)> rows;
    if (digits.isEmpty) {
      final me = ref.watch(meProvider).value?.extensionValue;
      final presence = ref.watch(presenceProvider);
      final dir = ref.watch(colleaguesProvider);
      final free = [
        for (final col in dir.value ?? const <Colleague>[])
          if (col.extensionValue != me &&
              presenceLook(
                    (presence[col.extensionValue] ?? col.presence).presence,
                  ) ==
                  PresenceLook.free)
            (col, presence[col.extensionValue] ?? col.presence),
      ];
      rows = [
        if (dir.hasValue) (_) => VpBand('${free.length} free now'),
        if (dir.hasValue && free.isEmpty)
          (_) => const VpEmpty('No colleagues are free right now.'),
        for (final (col, p) in free)
          (_) => _FreeRow(
            colleague: col,
            presence: p,
            selected: col.extensionValue == picked,
            onTap: () => onPick(
              col.extensionValue,
              '${col.name}, ext ${col.extensionValue}',
            ),
          ),
      ];
    } else {
      final matches = ref.watch(keypadMatchesProvider(typed));
      rows = [
        if (matches.isEmpty) (_) => const VpEmpty('No one matches.'),
        for (final m in matches)
          (stacked) => _MatchRow(
            match: m,
            selected: m.number == picked,
            stacked: stacked,
            onTap: () => onPick(m.number, m.label),
          ),
      ];
    }
    return LayoutBuilder(
      builder: (context, box) {
        final stacked = box.maxWidth < _stackBelow;
        return ListView(
          padding: EdgeInsets.zero,
          children: [header, for (final r in rows) r(stacked)],
        );
      },
    );
  }
}

/// Under [_stackBelow] dp the matches put their tag under the name, so the
/// name keeps the row's width (the narrowest split gives the list 240).
const double _stackBelow = 280;

/// `.av`: 40 px, initials, raised surface.
class _Initials extends StatelessWidget {
  const _Initials(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surfaceRaised, shape: BoxShape.circle),
      // A bare number has no initials: a handset, as on the call screens.
      child: initialsOf(name).contains(RegExp(r'\d'))
          ? VpSvgIcon(VpIcon.phone, size: 16, colour: c.textMuted)
          : Text(
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
    );
  }
}

/// Large text (above 130%): the rows stack their tag under the lines, and
/// each line may take two, so the names still read in a 240 dp pane.
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

/// Name (15 px 700) over the muted line (12 px), then the tag when the text
/// is large; one line each (two at large text), ending in an ellipsis.
class _Lines extends StatelessWidget {
  const _Lines({required this.title, required this.detail, this.tag});
  final String title;
  final String detail;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    // Stacked (a narrow pane or large text): up to two lines each.
    final lines = _largeText(context) || tag != null ? 2 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: VpType.body.copyWith(
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w700,
            fontVariations: const [FontVariation('wght', 700)],
            color: c.text,
          ),
        ),
        Text(
          detail,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: VpType.body.copyWith(
            fontSize: 12,
            height: 1.4,
            color: c.textMuted,
          ),
        ),
        if (tag != null)
          Text(
            tag!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VpType.body.copyWith(fontSize: 12, color: c.textMuted),
          ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.selected,
    required this.stacked,
    required this.onTap,
  });
  final KeypadMatch match;

  /// The tag under the lines rather than beside them (a narrow pane).
  final bool stacked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final m = match;
    final large = stacked || _largeText(context);
    return WideListRow(
      selected: selected,
      onTap: onTap,
      semanticLabel:
          '${m.name}, ${m.detail}, ${m.source.tag}. Puts the number in',
      children: [
        _Initials(m.name),
        Expanded(
          child: _Lines(
            title: m.name,
            detail: m.detail,
            tag: large ? m.source.tag : null,
          ),
        ),
        if (!large)
          Text(
            m.source.tag,
            style: VpType.body.copyWith(fontSize: 12, color: c.textMuted),
          ),
      ],
    );
  }
}

/// A colleague free now: the presence dot, then role, extension and
/// status, as in Contacts (without its call button: a tap fills the
/// keypad).
class _FreeRow extends StatelessWidget {
  const _FreeRow({
    required this.colleague,
    required this.presence,
    required this.selected,
    required this.onTap,
  });
  final Colleague colleague;
  final PresenceEntry presence;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final col = colleague;
    final sub = [
      col.role,
      col.extensionValue,
      presenceText(presence.presence),
    ].whereType<String>().join(' · ');
    return WideListRow(
      selected: selected,
      onTap: onTap,
      semanticLabel: '${col.name}, $sub. Puts the extension in',
      children: [
        PresenceAvatar(name: col.name, presence: presence.presence),
        Expanded(
          child: _Lines(title: col.name, detail: sub),
        ),
      ],
    );
  }
}
