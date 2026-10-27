import 'dart:convert';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone/src/messages.g.dart';
import 'package:vp_linphone/vp_linphone.dart';

/// Plays the Kotlin side: records every host call, answers or throws as told.
class FakeHost extends VpLinphoneHostApi {
  final List<List<Object?>> calls = [];
  PlatformException? nextError;
  String nextCallId = 'call-1';
  Uint8List log = Uint8List(0);

  Future<T> _rec<T>(String name, List<Object?> args, T value) async {
    calls.add([name, ...args]);
    final e = nextError;
    nextError = null;
    if (e != null) throw e;
    return value;
  }

  @override
  Future<void> start() => _rec('start', [], null);
  @override
  Future<void> stop() => _rec('stop', [], null);
  @override
  Future<void> register(
    String authUsername,
    String password,
    String domain,
    String outboundProxy,
    String displayName,
    int expiresSeconds,
    String? pushProvider,
    String? pushPrid,
    String? pushParam,
  ) => _rec('register', [
    authUsername,
    password,
    domain,
    outboundProxy,
    displayName,
    expiresSeconds,
    pushProvider,
    pushPrid,
    pushParam,
  ], null);
  @override
  Future<void> unregister() => _rec('unregister', [], null);
  @override
  Future<void> updatePush(String provider, String prid, String param) =>
      _rec('updatePush', [provider, prid, param], null);
  @override
  Future<String> call(String number, String? callerId) => _rec('call', [number, callerId], nextCallId);
  @override
  Future<void> answer(String callId) => _rec('answer', [callId], null);
  @override
  Future<void> decline(String callId) => _rec('decline', [callId], null);
  @override
  Future<void> toVoicemail(String callId) => _rec('toVoicemail', [callId], null);
  @override
  Future<void> hangup(String callId) => _rec('hangup', [callId], null);
  @override
  Future<void> hold(String callId) => _rec('hold', [callId], null);
  @override
  Future<void> resume(String callId) => _rec('resume', [callId], null);
  @override
  Future<void> setMuted(bool muted) => _rec('setMuted', [muted], null);
  @override
  Future<void> sendDtmf(String callId, String digits) => _rec('sendDtmf', [callId, digits], null);
  @override
  Future<void> transferBlind(String callId, String target) => _rec('transferBlind', [callId, target], null);
  @override
  Future<void> transferAttended(String callId, String consultCallId) =>
      _rec('transferAttended', [callId, consultCallId], null);
  @override
  Future<void> merge(String callIdA, String callIdB) => _rec('merge', [callIdA, callIdB], null);
  @override
  Future<void> setAudioRoute(AudioRouteMsg route) => _rec('setAudioRoute', [route], null);
  @override
  Future<Uint8List> exportLastCallLog() => _rec('exportLastCallLog', [], log);
}

const account = SipAccount(
  authUsername: 'app-abcde12345',
  password: 'testpasswordtestpassword',
  domain: 'democo.sip.voiceplatform.com.au',
  outboundProxy: 'sip:sip.voiceplatform.com.au:5061;transport=tls',
  displayName: 'Ava Nguyen',
  expiresSeconds: 600,
  push: PushParams(provider: 'fcm', prid: 'token-1', param: 'voiceplatform-app'),
);

CallMsg msg(String id, CallStateMsg state, {bool incoming = false, EndReasonMsg? end}) => CallMsg(
  id: id,
  incoming: incoming,
  state: state,
  remoteNumber: '+61491570737',
  remoteName: 'Ava Nguyen',
  startedAtMs: 1793070900000,
  connectedAtMs: state == CallStateMsg.connected ? 1793070905000 : null,
  muted: false,
  encrypted: true,
  hdAudio: true,
  endReason: end,
  headerCalled: incoming ? '+61355501201;label="Sales group"' : null,
  headerRepeat: incoming ? '3' : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHost host;
  late VpLinphoneEngine engine;

  setUp(() {
    host = FakeHost();
    engine = VpLinphoneEngine(hostApi: host);
  });

  test('the engine is a CallEngine', () {
    expect(engine, isA<CallEngine>());
  });

  test('Pigeon enums line up with the contract by index', () {
    List<String> names(List<Enum> v) => [for (final e in v) e.name];
    expect(names(RegStateMsg.values), names(RegistrationState.values));
    expect(names(RegFailureMsg.values), names(RegistrationFailure.values));
    expect(names(CallStateMsg.values), names(CallState.values));
    expect(names(EndReasonMsg.values), names(EndReason.values));
    expect(names(AudioRouteMsg.values), names(AudioRoute.values));
  });

  test('register passes the account and its RFC 8599 params once', () async {
    await engine.register(account);
    expect(host.calls.single, [
      'register',
      'app-abcde12345',
      'testpasswordtestpassword',
      'democo.sip.voiceplatform.com.au',
      'sip:sip.voiceplatform.com.au:5061;transport=tls',
      'Ava Nguyen',
      600,
      'fcm',
      'token-1',
      'voiceplatform-app',
    ]);
    expect(account.toString(), isNot(contains(account.password)));
  });

  test('register without push sends no pn params', () async {
    const desktop = SipAccount(
      authUsername: 'app-abcde12345',
      password: 'testpasswordtestpassword',
      domain: 'democo.sip.voiceplatform.com.au',
      outboundProxy: 'sip:sip.voiceplatform.com.au:5061;transport=tls',
      displayName: 'Ava',
      expiresSeconds: 600,
    );
    await engine.register(desktop);
    expect(host.calls.single.sublist(7), [null, null, null]);
  });

  test('updatePush, call with caller ID, and every call control', () async {
    await engine.updatePush(const PushParams(provider: 'fcm', prid: 'token-2', param: 'voiceplatform-app'));
    expect(await engine.call('0491 570 737', callerId: '+61355501201'), 'call-1');
    await engine.answer('call-2');
    await engine.decline('call-2');
    await engine.toVoicemail('call-2');
    await engine.hold('call-1');
    await engine.resume('call-1');
    await engine.setMuted(true);
    await engine.sendDtmf('call-1', '12#');
    await engine.transferBlind('call-1', '204');
    await engine.transferAttended('call-1', 'call-3');
    await engine.merge('call-1', 'call-3');
    await engine.setAudioRoute(AudioRoute.speaker);
    await engine.hangup('call-1');
    expect(host.calls.map((c) => c.first), [
      'updatePush',
      'call',
      'answer',
      'decline',
      'toVoicemail',
      'hold',
      'resume',
      'setMuted',
      'sendDtmf',
      'transferBlind',
      'transferAttended',
      'merge',
      'setAudioRoute',
      'hangup',
    ]);
    expect(host.calls[1], ['call', '0491 570 737', '+61355501201']);
    expect(host.calls[12], ['setAudioRoute', AudioRouteMsg.speaker]);
  });

  test('emergency numbers go straight to the platform side', () async {
    for (final n in ['000', '112', '106', '0000']) {
      await engine.call(n);
    }
    expect(host.calls.map((c) => c[1]), ['000', '112', '106', '0000']);
  });

  group('platform errors become CallEngineError', () {
    Future<Object?> fail(String code, Future<void> Function() f) async {
      host.nextError = PlatformException(code: code, message: 'm');
      try {
        await f();
      } catch (e) {
        return e;
      }
      return null;
    }

    test('codes', () async {
      expect(await fail('not_registered', () => engine.call('204')), isA<NotRegistered>());
      expect(await fail('microphone_denied', () => engine.answer('call-1')), isA<MicrophoneDenied>());
      final e = await fail('no_such_call', () => engine.hangup('call-9'));
      expect(e, isA<NoSuchCall>());
      expect((e as NoSuchCall).message, 'No call call-9');
      expect(await fail('invalid_state', () => engine.hold('call-1')), isA<InvalidState>());
      expect(await fail('channel-error', () => engine.start()), isA<InvalidState>());
    });
  });

  test('registration events', () async {
    final got = <RegistrationEvent>[];
    final sub = engine.registration.listen(got.add);
    engine.events.onRegistration(RegistrationMsg(state: RegStateMsg.progress));
    engine.events.onRegistration(RegistrationMsg(state: RegStateMsg.ok, sipCode: 200));
    engine.events.onRegistration(
      RegistrationMsg(state: RegStateMsg.failed, failure: RegFailureMsg.badCredentials, sipCode: 401),
    );
    await pumpEventQueue();
    expect(got.map((e) => e.state), [RegistrationState.progress, RegistrationState.ok, RegistrationState.failed]);
    expect(got.last.failure, RegistrationFailure.badCredentials);
    expect(got.last.sipCode, 401);
    await sub.cancel();
  });

  test('incoming call snapshot carries the parsed headers', () async {
    final got = <CallSnapshot>[];
    final sub = engine.calls.listen(got.add);
    engine.events.onCall(msg('call-1', CallStateMsg.incoming, incoming: true));
    await pumpEventQueue();
    final s = got.single;
    expect(s.direction, CallDirection.incoming);
    expect(s.state, CallState.incoming);
    expect(s.remoteNumber, '+61491570737');
    expect(s.incoming!.calledNumber, '+61355501201');
    expect(s.incoming!.calledLabel, 'Sales group');
    expect(s.incoming!.repeatCount, 3);
    expect(s.startedAt, DateTime.fromMillisecondsSinceEpoch(1793070900000, isUtc: true));
    expect(engine.activeCalls.single.id, 'call-1');
    await sub.cancel();
  });

  test('answered elsewhere ends the call and clears it', () async {
    final got = <CallSnapshot>[];
    final sub = engine.calls.listen(got.add);
    engine.events.onCall(msg('call-1', CallStateMsg.incoming, incoming: true));
    engine.events.onCall(msg('call-1', CallStateMsg.ended, incoming: true, end: EndReasonMsg.answeredElsewhere));
    await pumpEventQueue();
    expect(got.last.state, CallState.ended);
    expect(got.last.endReason, EndReason.answeredElsewhere);
    expect(engine.activeCalls, isEmpty);
    await sub.cancel();
  });

  test('outgoing calls have no IncomingInfo; flags pass through', () async {
    final got = <CallSnapshot>[];
    final sub = engine.calls.listen(got.add);
    engine.events.onCall(msg('call-2', CallStateMsg.connected));
    await pumpEventQueue();
    expect(got.single.incoming, isNull);
    expect(got.single.encrypted, isTrue);
    expect(got.single.hdAudio, isTrue);
    expect(got.single.connectedAt, isNotNull);
    await sub.cancel();
  });

  test('audio state', () async {
    final got = <AudioState>[];
    final sub = engine.audio.listen(got.add);
    engine.events.onAudio(
      AudioMsg(route: AudioRouteMsg.bluetooth, available: [AudioRouteMsg.earpiece, AudioRouteMsg.bluetooth]),
    );
    await pumpEventQueue();
    expect(got.single.route, AudioRoute.bluetooth);
    expect(got.single.available, {AudioRoute.earpiece, AudioRoute.bluetooth});
    await sub.cancel();
  });

  test('input level is mapped from dBm0 to 0..1', () async {
    final got = <double>[];
    final sub = engine.inputLevel.listen(got.add);
    for (final db in [-130.0, -60.0, -30.0, 0.0, 6.0, double.nan]) {
      engine.events.onInputLevel(db);
    }
    await pumpEventQueue();
    expect(got, [0.0, 0.0, 0.5, 1.0, 1.0, 0.0]);
    await sub.cancel();
  });

  test('the exported log is scrubbed again on the Dart side', () async {
    host.log = Uint8List.fromList(utf8.encode('2026 Oct 27 03:15:00.123Z ENGINE dial 0491570737\nok'));
    final out = utf8.decode(await engine.exportLastCallLog());
    expect(out, '2026 Oct 27 03:15:00.123Z ENGINE dial [n]\nok');
  });
}
