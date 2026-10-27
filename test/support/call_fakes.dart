import 'package:voiceplatform_app/calls/call_actions.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/calls/me_state.dart';
import 'package:voiceplatform_app/net/api.dart';

import '../../tool/mock_server/fixtures.dart' as fx;

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
}

class FixedPhoneContacts implements PhoneContactsSource {
  const FixedPhoneContacts(this.contacts);
  final List<PhoneContact> contacts;

  @override
  Future<List<PhoneContact>> readIfAllowed() async => contacts;
}

class PresetStatus extends MyStatusNotifier {
  PresetStatus(this.initial);
  final StatusStatus initial;
  final sent = <StatusInputStatus>[];

  @override
  StatusStatus? build() => initial;

  @override
  Future<void> set(StatusInputStatus s) async {
    sent.add(s);
    state = StatusStatus.fromJson(s.json!);
  }
}

class PresetOffline extends OfflineNotifier {
  @override
  bool build() => true;
}

/// The canvas sample data, through the contract's models.
List<Colleague> fixtureColleagues() => [
  for (final c in fx.colleagues)
    Colleague.fromJson({
      'userId': fx.uid(0xa, c['n']! as int),
      'name': c['name'],
      'initials': c['initials'],
      'extension': '${c['n']}',
      'team': ?c['team'],
      'role': ?c['role'],
      'mobile': ?c['mobile'],
      'presence': {'extension': '${c['n']}', 'presence': c['presence']},
    }),
];

List<SharedContact> fixtureShared() => [
  for (final s in fx.sharedContacts) SharedContact.fromJson(s),
];

List<CallerId> fixtureCallerIds() => [
  for (final c in fx.callerIds) CallerId.fromJson(c),
];
