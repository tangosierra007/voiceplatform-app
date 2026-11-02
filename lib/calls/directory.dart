import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../diagnostics/scrubber.dart';
import '../net/api.dart';
import '../net/events.dart';
import '../net/live_events.dart';
import 'numbers.dart';

/// `GET /directory/colleagues`: the colleagues with team and presence, and
/// the tenant's total.
final colleagueDirectoryProvider = FutureProvider<Colleagues>((ref) async {
  if (ref.watch(accessTokenProvider) == null) {
    return const Colleagues(total: 0, freeNow: 0, items: []);
  }
  return ref.watch(appApiProvider).directory.getDirectoryColleagues();
});

/// Colleagues with team, from `GET /directory/colleagues`.
final colleaguesProvider = FutureProvider<List<Colleague>>(
  (ref) async => (await ref.watch(colleagueDirectoryProvider.future)).items,
);

/// Teams (hunt groups) with their members' user ids.
final teamsProvider = FutureProvider<List<Team>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return ref.watch(appApiProvider).directory.getDirectoryTeams();
});

/// The tenant phonebook's "in the apps" entries.
final sharedContactsProvider = FutureProvider<List<SharedContact>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return ref.watch(appApiProvider).directory.getDirectorySharedContacts();
});

/// Live presence by extension: the colleagues' presence, then every
/// `presence.snapshot` and `presence` event from the stream (or its polling
/// fallback).
final presenceProvider =
    NotifierProvider<PresenceNotifier, Map<String, PresenceEntry>>(
      PresenceNotifier.new,
    );

class PresenceNotifier extends Notifier<Map<String, PresenceEntry>> {
  @override
  Map<String, PresenceEntry> build() {
    final live = ref.watch(liveEventsProvider);
    final sub = live.events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    final colleagues = ref.watch(colleaguesProvider).value ?? const [];
    return {for (final c in colleagues) c.extensionValue: c.presence};
  }

  void _onEvent(ServerEvent e) {
    switch (e.type) {
      case 'presence.snapshot':
        final items = (e.data['items'] as List?) ?? const [];
        state = {
          ...state,
          for (final i in items)
            if (i is Map<String, Object?>)
              (i['extension'] as String? ?? ''): PresenceEntry.fromJson(i),
        };
      case 'presence':
        final p = PresenceEntry.fromJson(e.data);
        state = {...state, p.extensionValue: p};
    }
  }
}

/// A phone contact from the device's address book: name, numbers and each
/// number's label (mobile, work, home…), held in memory, never sent
/// anywhere (APP12).
@immutable
class PhoneContact {
  const PhoneContact(
    this.name,
    this.numbers, {
    this.labels = const [],
    this.id,
  });
  final String name;
  final List<String> numbers;

  /// The label of the number at the same place in [numbers] ("mobile",
  /// "work", or the person's own); shorter when the phone gave none.
  final List<String> labels;

  /// The address book's own id for the contact, when the phone gave one.
  final String? id;

  /// Which contact is picked in Contacts (in memory only, like the rest).
  String get key => id ?? '$name\n${numbers.join('\n')}';

  /// The label of the number at [i]: the phone's, else "phone".
  String labelAt(int i) =>
      i < labels.length && labels[i].trim().isNotEmpty ? labels[i] : 'phone';
}

/// The labels [phoneLabelText] gives the phone's standard kinds, in lower
/// case: see [isStandardPhoneLabel].
final standardPhoneLabels = {
  for (final l in PhoneLabel.values)
    if (l != PhoneLabel.custom) phoneLabelText(l, null).toLowerCase(),
  'phone',
};

/// A standard kind's word, however it is written ("Work" typed as a
/// custom label is still "work"): nothing personal, so never scrubbed.
bool isStandardPhoneLabel(String label) =>
    standardPhoneLabels.contains(label.trim().toLowerCase());

/// A number's label in the words the phone's own Contacts app uses; the
/// person's own label as they wrote it (Apple's `_$!<…>!$_` markers off).
String phoneLabelText(PhoneLabel label, String? custom) => switch (label) {
  PhoneLabel.custom => () {
    final own = (custom ?? '')
        .replaceAll(r'_$!<', '')
        .replaceAll(r'>!$_', '')
        .trim();
    return own.isEmpty ? 'phone' : own;
  }(),
  PhoneLabel.appleWatch => 'Apple Watch',
  PhoneLabel.assistant => 'assistant',
  PhoneLabel.callback => 'callback',
  PhoneLabel.car => 'car',
  PhoneLabel.companyMain => 'company main',
  PhoneLabel.home => 'home',
  PhoneLabel.homeFax => 'home fax',
  PhoneLabel.iPhone => 'iPhone',
  PhoneLabel.isdn => 'ISDN',
  PhoneLabel.main => 'main',
  PhoneLabel.mobile => 'mobile',
  PhoneLabel.mms => 'MMS',
  PhoneLabel.other => 'other',
  PhoneLabel.otherFax => 'other fax',
  PhoneLabel.pager => 'pager',
  PhoneLabel.radio => 'radio',
  PhoneLabel.school => 'school',
  PhoneLabel.telex => 'telex',
  PhoneLabel.ttyTdd => 'TTY',
  PhoneLabel.work => 'work',
  PhoneLabel.workFax => 'work fax',
  PhoneLabel.workMobile => 'work mobile',
  PhoneLabel.workPager => 'work pager',
};

/// The device's address book. Read only when READ_CONTACTS is granted, and
/// asked for only when the Phone contacts tab is first opened ([request]).
/// What it reads stays in memory on the device (APP12): it never goes into a
/// request, and every name and number is registered with the diagnostics
/// scrubber so no log or crash report can carry it either.
abstract interface class PhoneContactsSource {
  /// Granted already; never shows a dialog.
  Future<bool> isGranted();

  /// Shows the system dialog once; true when granted.
  Future<bool> request();

  Future<List<PhoneContact>> readIfAllowed();
}

class DevicePhoneContacts implements PhoneContactsSource {
  const DevicePhoneContacts();

  @override
  Future<bool> isGranted() async {
    try {
      return await Permission.contacts.isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> request() async {
    try {
      return (await Permission.contacts.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<PhoneContact>> readIfAllowed() async {
    try {
      if (!await isGranted()) return const [];
      final all = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      return [
        for (final c in all)
          if ((c.displayName ?? '').isNotEmpty && c.phones.isNotEmpty)
            PhoneContact(
              c.displayName!,
              [for (final p in c.phones) p.number],
              labels: [
                for (final p in c.phones)
                  phoneLabelText(p.label.label, p.label.customLabel),
              ],
              id: c.id,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

final phoneContactsSourceProvider = Provider<PhoneContactsSource>(
  (ref) => const DevicePhoneContacts(),
);

/// Where address-book values are registered so diagnostics never carry them.
final addressBookScrubberProvider = Provider<void Function(Iterable<String>)>(
  (ref) => DiagnosticsScrubber.instance.rememberAddressBookValues,
);

final phoneContactsProvider = FutureProvider<List<PhoneContact>>((ref) async {
  final list = await ref.watch(phoneContactsSourceProvider).readIfAllowed();
  // The person's own labels can carry a name ("Sam's work"); the phone's
  // standard words can't, and stay readable in logs.
  ref.read(addressBookScrubberProvider)([
    for (final p in list) ...[
      p.name,
      ...p.numbers,
      for (final l in p.labels)
        if (!isStandardPhoneLabel(l)) l,
    ],
  ]);
  return list;
});

/// Back in the foreground with the address book allowed: read it again, so
/// names show the person's edits, an open phone contact's page shows its
/// new numbers, and a deleted contact's page closes. The shell watches it
/// while signed in.
final addressBookRefreshOnResumeProvider = Provider<void>((ref) {
  var live = true;
  final listener = AppLifecycleListener(
    onResume: () async {
      final granted = await ref.read(phoneContactsSourceProvider).isGranted();
      if (live && granted) ref.invalidate(phoneContactsProvider);
    },
  );
  ref.onDispose(() {
    live = false;
    listener.dispose();
  });
});

/// Who a number belongs to, for the keypad's match line and the call screens.
@immutable
class ContactMatch {
  const ContactMatch(this.name, {this.detail});
  final String name;

  /// Company, or `ext 206`.
  final String? detail;

  /// `Jordan Price, Harbour Cafe`.
  String get line => detail == null ? name : '$name, $detail';
}

/// Matches on the device only: colleagues by extension or mobile, shared
/// contacts and phone contacts by number. Exact matches first, then a
/// unique number that starts with what has been typed (6 digits or more).
class ContactMatcher {
  ContactMatcher({
    this.colleagues = const [],
    this.shared = const [],
    this.phone = const [],
  });

  final List<Colleague> colleagues;
  final List<SharedContact> shared;
  final List<PhoneContact> phone;

  List<(String, ContactMatch)> get _entries => [
    for (final c in colleagues) ...[
      (
        c.extensionValue,
        ContactMatch(c.name, detail: 'ext ${c.extensionValue}'),
      ),
      if (c.mobile != null) (nationalDigits(c.mobile!), ContactMatch(c.name)),
    ],
    for (final s in shared)
      for (final n in s.numbers)
        (nationalDigits(n.number), ContactMatch(s.name, detail: s.company)),
    for (final p in phone)
      for (final n in p.numbers) (nationalDigits(n), ContactMatch(p.name)),
  ];

  ContactMatch? match(String typed) {
    // A service code ("*97") is nobody's number.
    if (typed.contains(RegExp('[*#]'))) return null;
    final d = nationalDigits(typed);
    if (d.isEmpty) return null;
    final entries = _entries;
    for (final (n, m) in entries) {
      if (n == d) return m;
    }
    if (d.length < 6) return null;
    final starts = {
      for (final (n, m) in entries)
        if (n.startsWith(d)) n: m,
    };
    return starts.length == 1 ? starts.values.single : null;
  }
}

final contactMatcherProvider = Provider<ContactMatcher>(
  (ref) => ContactMatcher(
    colleagues: ref.watch(colleaguesProvider).value ?? const [],
    shared: ref.watch(sharedContactsProvider).value ?? const [],
    phone: ref.watch(phoneContactsProvider).value ?? const [],
  ),
);

/// What the presence dot and status text say, per spec 22.
enum PresenceLook { free, onCall, dnd, away }

PresenceLook presenceLook(Presence p) => switch (p) {
  Presence.available || Presence.mobileOnly => PresenceLook.free,
  Presence.onCall => PresenceLook.onCall,
  Presence.dnd => PresenceLook.dnd,
  _ => PresenceLook.away,
};

/// "Available", "On a call", "Do not disturb", "Away", "Offline",
/// "Available on mobile" (AppContacts; AppTransfer follows it, TJ 27 Oct).
String presenceText(Presence p) => switch (p) {
  Presence.available => 'Available',
  Presence.onCall => 'On a call',
  Presence.dnd => 'Do not disturb',
  Presence.away => 'Away',
  Presence.mobileOnly => 'Available on mobile',
  _ => 'Offline',
};
