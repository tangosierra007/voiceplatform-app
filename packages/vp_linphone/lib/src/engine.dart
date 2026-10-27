import 'dart:async';
import 'dart:convert';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'incoming_headers.dart';
import 'log_scrubber.dart';
import 'messages.g.dart';

/// Maps liblinphone's record volume (dBm0) to the 0..1 waveform level:
/// -60 dBm0 and below is 0, 0 dBm0 is 1, linear in between.
double levelFromDbm0(double dbm0) {
  if (dbm0.isNaN) return 0;
  return ((dbm0 + 60) / 60).clamp(0.0, 1.0);
}

/// [CallEngine] on liblinphone (Android): one Core in a foreground service,
/// reached through the Pigeon channel in `messages.g.dart`.
///
/// Credentials are write-only: [register] passes the password to the
/// platform side once and keeps no reference to it.
final class VpLinphoneEngine implements CallEngine {
  /// [voicemailUser] is the user part "To voicemail" redirects to (302 to
  /// `sip:<voicemailUser>@<domain>`); `*97` until the platform supplies the
  /// target.
  VpLinphoneEngine({VpLinphoneHostApi? hostApi, BinaryMessenger? binaryMessenger, this.voicemailUser = '*97'})
    : _host = hostApi ?? VpLinphoneHostApi(binaryMessenger: binaryMessenger) {
    _events = _Events(this);
    VpLinphoneEventsApi.setUp(_events, binaryMessenger: binaryMessenger);
  }

  final VpLinphoneHostApi _host;

  /// The voicemail target's user part, for example `*97`.
  final String voicemailUser;
  late final _Events _events;

  final _registration = StreamController<RegistrationEvent>.broadcast();
  final _calls = StreamController<CallSnapshot>.broadcast();
  final _audio = StreamController<AudioState>.broadcast();
  final _level = StreamController<double>.broadcast();
  final Map<String, CallSnapshot> _active = {};

  /// The receiving end of the Kotlin events, for tests that play the platform.
  @visibleForTesting
  VpLinphoneEventsApi get events => _events;

  // ------------------------------------------------------------ lifecycle

  @override
  Future<void> start() => _guard(_host.start);

  @override
  Future<void> stop() => _guard(_host.stop);

  // ------------------------------------------------------------ registration

  @override
  Future<void> register(SipAccount account) => _guard(
    () => _host.register(
      account.authUsername,
      account.password,
      account.domain,
      account.outboundProxy,
      account.displayName,
      account.expiresSeconds,
      account.instanceId,
      account.push?.provider,
      account.push?.prid,
      account.push?.param,
    ),
  );

  @override
  Future<void> unregister() => _guard(_host.unregister);

  @override
  Future<void> updatePush(PushParams push) => _guard(() => _host.updatePush(push.provider, push.prid, push.param));

  @override
  Stream<RegistrationEvent> get registration => _registration.stream;

  // ------------------------------------------------------------ calls

  /// Never refuses an emergency number (CLAUDE.md rule 8): the platform side
  /// places 000, 112 and 106 even when not registered or without the
  /// microphone permission.
  @override
  Future<String> call(String number, {String? callerId}) => _guard(() => _host.call(number, callerId));

  @override
  Future<void> answer(String callId) => _guard(() => _host.answer(callId), callId: callId);

  @override
  Future<void> decline(String callId) => _guard(() => _host.decline(callId), callId: callId);

  @override
  Future<void> toVoicemail(String callId) => _guard(() => _host.toVoicemail(callId, voicemailUser), callId: callId);

  @override
  Future<void> hangup(String callId) => _guard(() => _host.hangup(callId), callId: callId);

  @override
  Future<void> hold(String callId) => _guard(() => _host.hold(callId), callId: callId);

  @override
  Future<void> resume(String callId) => _guard(() => _host.resume(callId), callId: callId);

  @override
  Future<void> setMuted(bool muted) => _guard(() => _host.setMuted(muted));

  @override
  Future<void> sendDtmf(String callId, String digits) => _guard(() => _host.sendDtmf(callId, digits), callId: callId);

  @override
  Future<void> transferBlind(String callId, String target) =>
      _guard(() => _host.transferBlind(callId, target), callId: callId);

  @override
  Future<void> transferAttended(String callId, String consultCallId) =>
      _guard(() => _host.transferAttended(callId, consultCallId), callId: callId);

  @override
  Future<void> merge(String callIdA, String callIdB) => _guard(() => _host.merge(callIdA, callIdB), callId: callIdA);

  @override
  Future<void> setAudioRoute(AudioRoute route) => _guard(() => _host.setAudioRoute(AudioRouteMsg.values[route.index]));

  @override
  Stream<AudioState> get audio => _audio.stream;

  @override
  Stream<CallSnapshot> get calls => _calls.stream;

  @override
  List<CallSnapshot> get activeCalls => List.unmodifiable(_active.values);

  @override
  Stream<double> get inputLevel => _level.stream;

  @override
  Future<Uint8List> exportLastCallLog() async {
    final bytes = await _guard(_host.exportLastCallLog);
    // Already scrubbed line by line on the platform side; scrubbed again here.
    final text = utf8.decode(bytes, allowMalformed: true);
    return Uint8List.fromList(utf8.encode(LogScrubber().scrub(text)));
  }

  // ------------------------------------------------------------ plumbing

  Future<T> _guard<T>(Future<T> Function() body, {String? callId}) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw _error(e, callId);
    }
  }

  static CallEngineError _error(PlatformException e, String? callId) => switch (e.code) {
    'not_registered' => const NotRegistered(),
    'microphone_denied' => const MicrophoneDenied(),
    'no_such_call' => NoSuchCall(callId ?? '?'),
    _ => InvalidState(e.message ?? e.code),
  };

  void _onRegistration(RegistrationMsg m) {
    _registration.add(
      RegistrationEvent(
        RegistrationState.values[m.state.index],
        failure: m.failure == null ? null : RegistrationFailure.values[m.failure!.index],
        sipCode: m.sipCode,
      ),
    );
  }

  void _onCall(CallMsg m) {
    final s = CallSnapshot(
      id: m.id,
      direction: m.incoming ? CallDirection.incoming : CallDirection.outgoing,
      state: CallState.values[m.state.index],
      remoteNumber: m.remoteNumber,
      remoteName: m.remoteName,
      startedAt: _time(m.startedAtMs),
      connectedAt: _time(m.connectedAtMs),
      muted: m.muted,
      encrypted: m.encrypted,
      hdAudio: m.hdAudio,
      incoming: m.incoming
          ? IncomingHeaders.parse(
              called: m.headerCalled,
              alsoRinging: m.headerAlsoRinging,
              repeat: m.headerRepeat,
              lastAnswered: m.headerLastAnswered,
            )
          : null,
      endReason: m.endReason == null ? null : EndReason.values[m.endReason!.index],
    );
    if (s.state == CallState.ended) {
      _active.remove(s.id);
    } else {
      _active[s.id] = s;
    }
    _calls.add(s);
  }

  void _onAudio(AudioMsg m) {
    _audio.add(
      AudioState(
        route: AudioRoute.values[m.route.index],
        available: {for (final r in m.available) AudioRoute.values[r.index]},
      ),
    );
  }

  void _onInputLevel(double dbm0) => _level.add(levelFromDbm0(dbm0));

  static DateTime? _time(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

final class _Events implements VpLinphoneEventsApi {
  _Events(this._engine);
  final VpLinphoneEngine _engine;

  @override
  void onRegistration(RegistrationMsg event) => _engine._onRegistration(event);

  @override
  void onCall(CallMsg call) => _engine._onCall(call);

  @override
  void onAudio(AudioMsg audio) => _engine._onAudio(audio);

  @override
  void onInputLevel(double dbm0) => _engine._onInputLevel(dbm0);
}
