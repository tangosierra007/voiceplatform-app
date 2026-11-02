import 'dart:async';

import 'package:voiceplatform_app/calls/call_actions.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/calls/me_state.dart';
import 'package:voiceplatform_app/engine/phone_extras.dart';
import 'package:voiceplatform_app/features/recents/media_player.dart';
import 'package:voiceplatform_app/net/api.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import 'fake_api.dart';

class FakeMic implements MicPermission {
  FakeMic({this.granted = true, this.grantOnRequest = true});
  bool granted;
  bool grantOnRequest;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requests++;
    granted = grantOnRequest;
    return granted;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  int notificationAsks = 0;
  int bluetoothAsks = 0;

  @override
  Future<void> requestNotifications() async => notificationAsks++;

  @override
  Future<void> requestBluetooth() async => bluetoothAsks++;
}

class FixedPhoneContacts implements PhoneContactsSource {
  FixedPhoneContacts(
    this.contacts, {
    this.granted = true,
    this.grantOnRequest = true,
  });
  final List<PhoneContact> contacts;
  bool granted;
  bool grantOnRequest;
  int requests = 0;
  int reads = 0;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requests++;
    granted = granted || grantOnRequest;
    return granted;
  }

  @override
  Future<List<PhoneContact>> readIfAllowed() async {
    reads++;
    return granted ? contacts : const [];
  }
}

class PresetStatus extends MyStatusNotifier {
  PresetStatus(this.initial);
  final StatusStatus initial;
  final sent = <StatusInputStatus>[];
  final sentUntil = <DateTime?>[];

  @override
  StatusStatus? build() => initial;

  @override
  Future<void> set(StatusInputStatus s, {DateTime? dndUntil}) async {
    sent.add(s);
    sentUntil.add(dndUntil);
    state = StatusStatus.fromJson(s.json!);
  }
}

class PresetOffline extends OfflineNotifier {
  @override
  bool build() => true;
}

/// The canvas sample data, through the contract's models. With [now], a
/// colleague on a call has been on it for the fixture's go seconds.
List<Colleague> fixtureColleagues({DateTime? now}) => [
  for (final c in fx.colleagues)
    Colleague.fromJson({
      'userId': fx.uid(0xa, c['n']! as int),
      'name': c['name'],
      'initials': c['initials'],
      'extension': '${c['n']}',
      'team': ?c['team'],
      'role': ?c['role'],
      'mobile': ?c['mobile'],
      'presence': {
        'extension': '${c['n']}',
        'presence': c['presence'],
        if (now != null && c['ago'] != null)
          'since': now
              .subtract(Duration(seconds: c['ago']! as int))
              .toUtc()
              .toIso8601String(),
      },
    }),
];

Colleagues fixtureDirectory({DateTime? now}) {
  final items = fixtureColleagues(now: now);
  return Colleagues(
    total: fx.colleaguesTotal,
    freeNow: items
        .where(
          (c) =>
              c.presence.presence == Presence.available ||
              c.presence.presence == Presence.mobileOnly,
        )
        .length,
    items: items,
  );
}

List<Team> fixtureTeams() => [for (final t in fx.teams) Team.fromJson(t)];

/// AppRecents' calls for a filter, as the mock server filters them.
HistoryPage fixtureHistory({String filter = 'all', bool mine = false}) =>
    HistoryPage(
      items: [
        for (final h in fx.history)
          if ((filter == 'all' ||
                  (filter == 'missed' &&
                      (h['outcome'] == 'missed' ||
                          h['outcome'] == 'voicemail')) ||
                  (filter == 'voicemail' && h['outcome'] == 'voicemail')) &&
              (!mine || h['mine'] == true))
            HistoryEntry.fromJson(h),
      ],
      counts: const Counts(missed: 2, voicemail: 2),
    );

List<VoicemailBox> fixtureBoxes() => [
  for (final b in fx.voicemailBoxes) VoicemailBox.fromJson(b),
];

List<VoicemailMessage> fixtureVoicemails({String? box}) => [
  for (final v in fx.voicemails)
    if (box == null || v['boxId'] == box) VoicemailMessage.fromJson(v),
];

List<Greeting> fixtureGreetings() => [
  for (final g in fx.greetings) Greeting.fromJson(g),
];

/// A player that plays nothing and records what it was asked.
class FakeMediaPlayer implements MediaPlayer {
  final opened = <(Uri, Map<String, String>)>[];
  final speaker = <bool>[];
  final _out = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  void emit(PlaybackState s) {
    _state = s;
    _out.add(s);
  }

  @override
  Stream<PlaybackState> get states => _out.stream;

  @override
  PlaybackState get state => _state;

  @override
  Future<void> open(Uri url, Map<String, String> headers) async {
    opened.add((url, headers));
    emit(const PlaybackState(duration: Duration(seconds: 75)));
  }

  @override
  Future<void> play() async => emit(_state.copyWith(playing: true));

  @override
  Future<void> pause() async => emit(_state.copyWith(playing: false));

  @override
  Future<void> seek(Duration to) async => emit(_state.copyWith(position: to));

  @override
  Future<void> setSpeaker(bool on) async => speaker.add(on);

  @override
  Future<void> stop() async => emit(const PlaybackState());

  @override
  Future<void> dispose() => _out.close();
}

List<SharedContact> fixtureShared() => [
  for (final s in fx.sharedContacts) SharedContact.fromJson(s),
];

List<CallerId> fixtureCallerIds() => [
  for (final c in fx.callerIds) CallerId.fromJson(c),
];

List<SmsLine> fixtureLines() => [
  for (final l in fx.smsLines) SmsLine.fromJson(l),
];

ThreadPage fixtureThreads({String? lineId}) {
  final items = [
    for (final t in fx.threads)
      if (lineId == null || t['lineId'] == lineId) Thread.fromJson(t),
  ];
  return ThreadPage(
    items: items,
    unreadTotal: items.fold(0, (n, t) => n + t.unread),
  );
}

List<Message> fixtureThreadMessages(String id) => [
  for (final m in fx.threadMessages[id] ?? const <Map<String, Object?>>[])
    Message.fromJson(m),
];

CallSettings fixtureCallSettings() => CallSettings.fromJson(fx.callSettings);

OfficeHours fixtureOfficeHours() =>
    OfficeHours.fromJson(fx.officeHours('schedule'));

List<DeviceSummary> fixtureDevices() => [
  for (final d in fx.devices) DeviceSummary.fromJson(d),
];

List<Recording> fixtureRecordings() => [
  for (final r in fx.recordings) Recording.fromJson(r),
];

/// Pushes and battery facts on demand.
class FakeExtras implements PhoneExtras {
  FakeExtras({this.batteryStatus});
  final pushController = StreamController<VpPushMessage>.broadcast();
  VpBatteryStatus? batteryStatus;
  int batterySettingsOpened = 0;

  void push(VpPushType type) =>
      pushController.add(VpPushMessage(type, 'p-${type.name}'));

  @override
  Stream<VpPushMessage> get pushes => pushController.stream;

  @override
  Future<List<VpPushMessage>> takePendingPushes() async => const [];

  @override
  Future<VpBatteryStatus?> battery() async => batteryStatus;

  @override
  Future<void> openBatterySettings() async => batterySettingsOpened++;
}

/// Voicemail as the API keeps it, for the count tests: heard and deleted
/// change what `GET /history`'s counts, the boxes' new counts and `/me`'s
/// Recents badge say (`newVoicemailCount`). Its [routes] answer the app's
/// read and delete; [hold] keeps the next answer back until completed, and
/// [failNext] refuses it.
class VoicemailServer {
  final heard = <String, bool>{
    for (final v in fx.voicemails) v['id']! as String: v['heard']! as bool,
  };
  final deleted = <String>{};
  Completer<void>? hold;
  bool failNext = false;

  Iterable<Map<String, Object?>> get _live => [
    for (final v in fx.voicemails)
      if (!deleted.contains(v['id'])) {...v, 'heard': heard[v['id']]},
  ];

  int get newCount => _live.where((v) => v['heard'] != true).length;

  HistoryPage history({String filter = 'all', bool mine = false}) {
    final page = fixtureHistory(filter: filter, mine: mine);
    return HistoryPage(
      items: page.items,
      counts: Counts(missed: page.counts.missed, voicemail: newCount),
    );
  }

  List<VoicemailBox> boxes() => [
    for (final b in fx.voicemailBoxes)
      VoicemailBox.fromJson({
        ...b,
        'newCount': _live
            .where((v) => v['boxId'] == b['id'] && v['heard'] != true)
            .length,
      }),
  ];

  List<VoicemailMessage> messages({String? box}) => [
    for (final v in _live)
      if (box == null || v['boxId'] == box) VoicemailMessage.fromJson(v),
  ];

  Me me() {
    final m = fx.me(status: 'available');
    return Me.fromJson({
      ...m,
      'badges': {'recents': newCount, 'messages': 1},
    });
  }

  Future<Object?> _answer(void Function() change) async {
    final h = hold;
    hold = null;
    if (h != null) await h.future;
    if (failNext) {
      failNext = false;
      return (500, {'error': 'internal', 'message': 'Try again'});
    }
    change();
    return null;
  }

  Map<String, Object? Function(SeenRequest r)> get routes => {
    for (final v in fx.voicemails) ...{
      'POST /voicemail/messages/${v['id']}/read': (r) =>
          _answer(() => heard[v['id']! as String] = r.body.contains('true')),
      'POST /voicemail/messages/${v['id']}/delete': (_) =>
          _answer(() => deleted.add(v['id']! as String)),
      'POST /voicemail/messages/${v['id']}/media-url': (_) => {
        'url': '/app/v1/media/token-${v['id']}',
        'expiresAt': '2026-10-27T00:15:00.000Z',
      },
    },
  };
}
