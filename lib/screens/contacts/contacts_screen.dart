import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth.dart';
import '../../calls/call_actions.dart';
import '../../calls/directory.dart';
import '../../calls/numbers.dart';
import '../../emergency/emergency.dart';
import '../../features/recents/recents_format.dart';
import '../../net/api.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_preference.dart';
import '../../widgets/vp_controls.dart';
import '../../widgets/vp_icons.dart';
import '../../widgets/vp_list.dart';
import '../calls/transfer_screen.dart' show PresenceAvatar;

enum ContactsTab { colleagues, teams, phone }

final contactsTabProvider = NotifierProvider<ContactsTabNotifier, ContactsTab>(
  ContactsTabNotifier.new,
);

class ContactsTabNotifier extends Notifier<ContactsTab> {
  @override
  ContactsTab build() => ContactsTab.colleagues;
  void set(ContactsTab t) => state = t;
}

/// Whether READ_CONTACTS has been asked for. Asked once, the first time the
/// Phone contacts tab opens; never from anywhere else.
const contactsAskedKey = 'contacts.permission_asked';

/// The Phone contacts tab's view of the permission.
enum PhoneAccess { unknown, granted, refused }

final phoneAccessProvider = NotifierProvider<PhoneAccessNotifier, PhoneAccess>(
  PhoneAccessNotifier.new,
);

class PhoneAccessNotifier extends Notifier<PhoneAccess> {
  @override
  PhoneAccess build() => PhoneAccess.unknown;

  /// On opening the Phone contacts tab: granted already, or ask the first
  /// time only. Refusing leaves everything else working.
  Future<void> onTabOpened() async {
    final source = ref.read(phoneContactsSourceProvider);
    if (await source.isGranted()) {
      state = PhoneAccess.granted;
      ref.invalidate(phoneContactsProvider);
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(contactsAskedKey) ?? false) {
      state = PhoneAccess.refused;
      return;
    }
    await prefs.setBool(contactsAskedKey, true);
    final ok = await source.request();
    state = ok ? PhoneAccess.granted : PhoneAccess.refused;
    if (ok) ref.invalidate(phoneContactsProvider);
  }
}

/// AppContacts: Colleagues (live presence), Teams, and the phone's own
/// contacts with the shared phonebook's entries marked "In the apps".
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (ref.read(contactsTabProvider) == ContactsTab.phone) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(phoneAccessProvider.notifier).onTabOpened(),
      );
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _select(ContactsTab t) {
    ref.read(contactsTabProvider.notifier).set(t);
    if (t == ContactsTab.phone) {
      unawaited(ref.read(phoneAccessProvider.notifier).onTabOpened());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    final tab = ref.watch(contactsTabProvider);
    final me = ref.watch(meProvider).value;
    final q = _query.text.trim();
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
                const VpPageTitle('Contacts'),
                const SizedBox(height: 12),
                TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  style: VpType.body.copyWith(color: c.text),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search ${me?.tenantName ?? 'contacts'}',
                    hintStyle: VpType.body.copyWith(color: c.textMuted),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: VpSvgIcon(
                        VpIcon.search,
                        size: 18,
                        colour: c.textMuted,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 36,
                    ),
                    filled: true,
                    fillColor: c.surface,
                    constraints: const BoxConstraints(minHeight: 48),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(VpRadius.md),
                      borderSide: BorderSide(color: c.borderStrong),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(VpRadius.md),
                      borderSide: BorderSide(color: c.focus, width: 2),
                    ),
                    semanticCounterText: 'Search contacts',
                  ),
                ),
                const SizedBox(height: 12),
                VpSeg<ContactsTab>(
                  label: 'Show',
                  options: const [
                    (ContactsTab.colleagues, 'Colleagues'),
                    (ContactsTab.teams, 'Teams'),
                    (ContactsTab.phone, 'Phone contacts'),
                  ],
                  value: tab,
                  onChanged: _select,
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (tab) {
              ContactsTab.colleagues => _Colleagues(query: q),
              ContactsTab.teams => _Teams(query: q),
              ContactsTab.phone => _PhoneContacts(query: q),
            },
          ),
        ],
      ),
    );
  }
}

bool _matches(String q, List<String?> fields) {
  if (q.isEmpty) return true;
  final lower = q.toLowerCase();
  final digits = nationalDigits(q);
  for (final f in fields) {
    if (f == null) continue;
    if (f.toLowerCase().contains(lower)) return true;
    if (digits.length >= 2 && nationalDigits(f).contains(digits)) return true;
  }
  return false;
}

/// Free now: available, or available on mobile.
bool _isFree(Presence p) => presenceLook(p) == PresenceLook.free;

class _Colleagues extends ConsumerWidget {
  const _Colleagues({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(colleagueDirectoryProvider);
    final presence = ref.watch(presenceProvider);
    final list = dir.value?.items ?? const <Colleague>[];
    // The free count is counted from live presence, not a fixed figure.
    final free = presence.isEmpty
        ? (dir.value?.freeNow ?? 0)
        : presence.values.where((p) => _isFree(p.presence)).length;
    final total = dir.value?.total ?? list.length;
    final shown = [
      for (final col in list)
        if (_matches(query, [
          col.name,
          col.extensionValue,
          col.team,
          col.role,
          col.mobile,
        ]))
          col,
    ];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(colleagueDirectoryProvider);
        try {
          await ref.read(colleagueDirectoryProvider.future);
        } catch (_) {}
      },
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (dir.hasValue)
            VpBand(
              '$total ${total == 1 ? 'colleague' : 'colleagues'} · '
              '$free free now',
            ),
          if (dir.hasError && !dir.hasValue)
            const VpEmpty("Colleagues didn't load. Pull down to try again.")
          else if (dir.hasValue && shown.isEmpty)
            VpEmpty(query.isEmpty ? 'No colleagues yet.' : 'No one matches.'),
          for (final col in shown)
            ColleagueRow(
              colleague: col,
              presence: presence[col.extensionValue] ?? col.presence,
            ),
        ],
      ),
    );
  }
}

/// One colleague: avatar with the presence dot, name, then role, extension,
/// status and, on a call, how long.
class ColleagueRow extends ConsumerWidget {
  const ColleagueRow({
    super.key,
    required this.colleague,
    required this.presence,
  });
  final Colleague colleague;
  final PresenceEntry presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final col = colleague;
    return VpRow(
      children: [
        ExcludeSemantics(
          child: PresenceAvatar(name: col.name, presence: presence.presence),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PresenceLine(colleague: col, presence: presence),
        ),
        const SizedBox(width: 8),
        VpRoundIconButton(
          icon: VpIcon.phone,
          label: 'Call ${col.name}',
          onPressed: () => dialNumber(context, ref, col.extensionValue),
        ),
      ],
    );
  }
}

/// The subtitle ticks once a second while the colleague is on a call.
class _PresenceLine extends ConsumerStatefulWidget {
  const _PresenceLine({required this.colleague, required this.presence});
  final Colleague colleague;
  final PresenceEntry presence;

  @override
  ConsumerState<_PresenceLine> createState() => _PresenceLineState();
}

class _PresenceLineState extends ConsumerState<_PresenceLine> {
  Timer? _tick;

  bool get _onCall =>
      widget.presence.presence == Presence.onCall &&
      widget.presence.since != null;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_PresenceLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_onCall && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_onCall) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.presence;
    final col = widget.colleague;
    final now = ref.watch(clockProvider)();
    final status = switch (p.presence) {
      Presence.onCall when p.since != null =>
        'On a call · ${minutesSeconds(now.difference(p.since!).inSeconds)}',
      Presence.dnd when p.dndUntil != null =>
        'Do not disturb until ${clockTime(p.dndUntil!.toLocal())}',
      _ => presenceText(p.presence),
    };
    final sub = [
      col.role,
      col.extensionValue,
      status,
    ].whereType<String>().join(' · ');
    return Semantics(
      label: '${col.name}, $sub',
      excludeSemantics: true,
      child: VpRowText(title: col.name, subtitle: sub),
    );
  }
}

class _Teams extends ConsumerStatefulWidget {
  const _Teams({required this.query});
  final String query;

  @override
  ConsumerState<_Teams> createState() => _TeamsState();
}

class _TeamsState extends ConsumerState<_Teams> {
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider);
    final colleagues = {
      for (final c
          in ref.watch(colleaguesProvider).value ?? const <Colleague>[])
        c.userId: c,
    };
    final presence = ref.watch(presenceProvider);
    final list = teams.value ?? const <Team>[];
    final shown = [
      for (final t in list)
        if (_matches(widget.query, [t.name, t.number])) t,
    ];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(teamsProvider);
        try {
          await ref.read(teamsProvider.future);
        } catch (_) {}
      },
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (teams.hasValue)
            VpBand('${list.length} ${list.length == 1 ? 'team' : 'teams'}'),
          if (teams.hasError && !teams.hasValue)
            const VpEmpty("Teams didn't load. Pull down to try again.")
          else if (teams.hasValue && shown.isEmpty)
            VpEmpty(
              widget.query.isEmpty ? 'No teams yet.' : 'No team matches.',
            ),
          for (final t in shown) ...[
            _teamRow(context, t, colleagues, presence),
            if (_open.contains(t.id))
              for (final id in t.members)
                if (colleagues[id] case final col?)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: ColleagueRow(
                      colleague: col,
                      presence: presence[col.extensionValue] ?? col.presence,
                    ),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _teamRow(
    BuildContext context,
    Team t,
    Map<String, Colleague> colleagues,
    Map<String, PresenceEntry> presence,
  ) {
    final c = context.vp;
    // Live: members free now, from presence; the server's count until then.
    final members = [for (final id in t.members) ?colleagues[id]];
    final free = members.isEmpty
        ? t.freeCount
        : members
              .where(
                (m) => _isFree(
                  (presence[m.extensionValue] ?? m.presence).presence,
                ),
              )
              .length;
    final number = t.number;
    final sub = [
      '${t.memberCount} ${t.memberCount == 1 ? 'person' : 'people'}',
      '$free free now',
      if (number != null) formatAuNumber(number),
    ].join(' · ');
    final open = _open.contains(t.id);
    void toggle() =>
        setState(() => open ? _open.remove(t.id) : _open.add(t.id));
    return VpRow(
      onTap: toggle,
      semanticLabel: '${t.name}, $sub, ${open ? 'hide' : 'show'} members',
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: ExcludeSemantics(
            child: Text(
              initialsOf(t.name),
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
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ExcludeSemantics(
            child: VpRowText(title: t.name, subtitle: sub),
          ),
        ),
        if (number != null) ...[
          const SizedBox(width: 8),
          VpRoundIconButton(
            icon: VpIcon.phone,
            label: 'Call ${t.name}',
            onPressed: () => dialNumber(context, ref, number),
          ),
        ],
      ],
    );
  }
}

class _PhoneContacts extends ConsumerWidget {
  const _PhoneContacts({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(phoneAccessProvider);
    final shared = ref.watch(sharedContactsProvider).value ?? const [];
    final phone = access == PhoneAccess.granted
        ? ref.watch(phoneContactsProvider).value ?? const <PhoneContact>[]
        : const <PhoneContact>[];
    final sharedShown = [
      for (final s in shared)
        if (_matches(query, [
          s.name,
          s.company,
          for (final n in s.numbers) n.number,
        ]))
          s,
    ];
    final phoneShown = [
      for (final p in phone)
        if (_matches(query, [p.name, ...p.numbers])) p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (sharedShown.isNotEmpty) ...[
          const VpBand('Shared phonebook'),
          for (final s in sharedShown)
            for (final n in s.numbers)
              _NumberRow(
                name: s.name,
                detail: [
                  s.company,
                  formatAuNumber(n.number),
                ].whereType<String>().where((d) => d != s.name).join(' · '),
                number: n.number,
                inTheApps: true,
              ),
        ],
        const VpBand('On this phone'),
        switch (access) {
          PhoneAccess.unknown => const SizedBox(height: 48),
          PhoneAccess.refused => const _NoAccess(),
          PhoneAccess.granted when phoneShown.isEmpty => VpEmpty(
            query.isEmpty ? 'No contacts on this phone.' : 'No one matches.',
          ),
          PhoneAccess.granted => Column(
            children: [
              for (final p in phoneShown)
                _NumberRow(
                  name: p.name,
                  detail: formatAuNumber(p.numbers.first),
                  number: p.numbers.first,
                ),
            ],
          ),
        },
      ],
    );
  }
}

class _NoAccess extends ConsumerWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Your phone's contacts aren't shown. Allow Contacts in Settings to "
          'see them here. They stay on this phone and are never uploaded.',
          style: vpMuted(context, size: 14, line: 20),
        ),
        const SizedBox(height: 4),
        VpLink(
          'Open Settings',
          onTap: () => ref.read(micPermissionProvider).openSettings(),
        ),
      ],
    ),
  );
}

class _NumberRow extends ConsumerWidget {
  const _NumberRow({
    required this.name,
    required this.detail,
    required this.number,
    this.inTheApps = false,
  });
  final String name;
  final String detail;
  final String number;
  final bool inTheApps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vp;
    return VpRow(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: ExcludeSemantics(
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
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            label: '$name, $detail${inTheApps ? ', in the apps' : ''}',
            excludeSemantics: true,
            child: VpRowText(title: name, subtitle: detail),
          ),
        ),
        if (inTheApps) ...[
          const SizedBox(width: 8),
          ExcludeSemantics(child: _Tag('In the apps')),
        ],
        const SizedBox(width: 8),
        VpRoundIconButton(
          icon: VpIcon.phone,
          label: 'Call $name',
          onPressed: () => dialNumber(context, ref, number),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.vp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.border),
      ),
      child: Text(
        text,
        style: VpType.caption.copyWith(
          fontSize: 11,
          color: c.textMuted,
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 700)],
        ),
      ),
    );
  }
}
