import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../net/api.dart';
import '../net/events.dart';
import '../net/live_events.dart';
import 'numbers.dart';

/// Colleagues with team, from `GET /directory/colleagues`.
final colleaguesProvider = FutureProvider<List<Colleague>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return (await ref.watch(appApiProvider).directory.getDirectoryColleagues())
      .items;
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

/// A phone contact from the device's address book: name and numbers only,
/// held in memory, never sent anywhere (APP12).
@immutable
class PhoneContact {
  const PhoneContact(this.name, this.numbers);
  final String name;
  final List<String> numbers;
}

/// Reads the address book only when READ_CONTACTS is already granted; it is
/// never asked for here (the Contacts tab asks, in 4.4).
abstract interface class PhoneContactsSource {
  Future<List<PhoneContact>> readIfAllowed();
}

class DevicePhoneContacts implements PhoneContactsSource {
  const DevicePhoneContacts();

  @override
  Future<List<PhoneContact>> readIfAllowed() async {
    try {
      if (!await Permission.contacts.isGranted) return const [];
      final all = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      return [
        for (final c in all)
          if ((c.displayName ?? '').isNotEmpty && c.phones.isNotEmpty)
            PhoneContact(c.displayName!, [for (final p in c.phones) p.number]),
      ];
    } catch (_) {
      return const [];
    }
  }
}

final phoneContactsSourceProvider = Provider<PhoneContactsSource>(
  (ref) => const DevicePhoneContacts(),
);

final phoneContactsProvider = FutureProvider<List<PhoneContact>>(
  (ref) => ref.watch(phoneContactsSourceProvider).readIfAllowed(),
);

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
