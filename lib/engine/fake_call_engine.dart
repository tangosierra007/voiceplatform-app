import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:call_engine/call_engine.dart';

/// How the far end answers outgoing calls placed on a [FakeCallEngine].
class OutgoingScript {
  const OutgoingScript({
    this.ringAfter = const Duration(milliseconds: 400),
    this.answerAfter = const Duration(seconds: 2),
    this.outcome = OutgoingOutcome.answer,
  });

  /// Dialling to ringing. Null stays dialling until the test moves it.
  final Duration? ringAfter;

  /// Ringing to [outcome]. Null stays ringing until the test moves it.
  final Duration? answerAfter;
  final OutgoingOutcome outcome;

  /// Nothing happens by itself; the test drives every step with `remote*`.
  static const manual = OutgoingScript(ringAfter: null, answerAfter: null);
}

enum OutgoingOutcome { answer, busy, noAnswer, failed }

/// A complete, in-memory [CallEngine] for the UI, widget tests and goldens.
///
/// Implements every method with the same state rules a real engine keeps,
/// plus `simulate*` and `remote*` hooks to script what the far end and the
/// platform do: incoming calls with [IncomingInfo], answers elsewhere,
/// remote hold, registration failures, audio devices, input level.
///
/// It never touches the network, and like the real engine it keeps the SIP
/// password write-only: nothing returns it and no event carries it.
class FakeCallEngine implements CallEngine {
  FakeCallEngine({
    this.outgoing = const OutgoingScript(),
    this.registerAfter = const Duration(milliseconds: 200),
    this.encrypted = true,
    this.hdAudio = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// What the far end does with outgoing calls.
  OutgoingScript outgoing;

  /// Registration progress to ok (or to the failure set with
  /// [failNextRegistration]). Zero completes in the same microtask turn.
  Duration registerAfter;

  /// Tags the next connected calls carry.
  bool encrypted;
  bool hdAudio;

  /// When false, `call` and `answer` throw [MicrophoneDenied] (AppMicrophone).
  bool microphoneGranted = true;

  final DateTime Function() _clock;

  final _registration = StreamController<RegistrationEvent>.broadcast();
  final _calls = StreamController<CallSnapshot>.broadcast();
  final _audio = StreamController<AudioState>.broadcast();
  final _level = StreamController<double>.broadcast();

  final Map<String, CallSnapshot> _active = {};
  final List<Timer> _timers = [];
  final List<String> _log = [];
  Timer? _levelTimer;
  int _levelTick = 0;
  int _nextId = 1;

  bool _started = false;
  SipAccount? _account;
  RegistrationState _regState = RegistrationState.none;
  RegistrationFailure? _failNext;
  int? _failNextCode;
  PushParams? _push;
  bool _muted = false;
  AudioState _audioState = const AudioState(
    route: AudioRoute.earpiece,
    available: {AudioRoute.earpiece, AudioRoute.speaker},
  );

  /// Calls this test has merged into a local 3-way.
  final Set<String> merged = {};

  /// Digits sent per call, for assertions.
  final Map<String, String> dtmfSent = {};

  /// Transfer targets per call, for assertions.
  final Map<String, String> transferredTo = {};

  // ---------------------------------------------------------------- state

  bool get isStarted => _started;
  RegistrationState get registrationState => _regState;

  /// The registered identity without its password.
  String? get registeredAs =>
      _account == null ? null : '${_account!.authUsername}@${_account!.domain}';
  PushParams? get pushParams => _push;
  bool get muted => _muted;
  AudioState get audioState => _audioState;

  @override
  Stream<RegistrationEvent> get registration => _registration.stream;

  @override
  Stream<CallSnapshot> get calls => _calls.stream;

  @override
  Stream<AudioState> get audio => _audio.stream;

  @override
  Stream<double> get inputLevel => _level.stream;

  @override
  List<CallSnapshot> get activeCalls => List.unmodifiable(_active.values);

  // ------------------------------------------------------------ lifecycle

  @override
  Future<void> start() async {
    _started = true;
    _logLine('engine started');
  }

  @override
  Future<void> stop() async {
    for (final id in _active.keys.toList()) {
      _end(id, EndReason.local);
    }
    _cancelTimers();
    if (_regState == RegistrationState.ok) {
      _setReg(const RegistrationEvent(RegistrationState.cleared));
    }
    _started = false;
    _logLine('engine stopped');
  }

  @override
  Future<void> register(SipAccount account) async {
    _requireStarted();
    _account = account;
    _push = account.push;
    _setReg(const RegistrationEvent(RegistrationState.progress));
    _logLine('register ${account.authUsername}@${account.domain}');
    void finish() {
      if (_account != account) return;
      final failure = _failNext;
      if (failure != null) {
        _failNext = null;
        _setReg(
          RegistrationEvent(
            RegistrationState.failed,
            failure: failure,
            sipCode: _failNextCode,
          ),
        );
        _failNextCode = null;
      } else {
        _setReg(const RegistrationEvent(RegistrationState.ok, sipCode: 200));
      }
    }

    if (registerAfter == Duration.zero) {
      finish();
    } else {
      _after(registerAfter, finish);
    }
  }

  @override
  Future<void> unregister() async {
    for (final id in _active.keys.toList()) {
      _end(id, EndReason.local);
    }
    _account = null;
    _push = null;
    _setReg(const RegistrationEvent(RegistrationState.cleared));
  }

  @override
  Future<void> updatePush(PushParams push) async {
    _push = push;
    _logLine('push params updated');
  }

  // ---------------------------------------------------------------- calls

  @override
  Future<String> call(String number, {String? callerId}) async {
    // Emergency numbers always go to the phone's own dialler, ahead of every
    // other check (started, registered, microphone): the app never places one
    // itself (decision 139 as amended 27 Oct; APP6).
    if (isEmergencyNumber(number)) throw const EmergencyNumberUseDialler();
    _requireStarted();
    if (_regState != RegistrationState.ok) throw const NotRegistered();
    if (!microphoneGranted) throw const MicrophoneDenied();
    final id = _newId();
    _emit(
      CallSnapshot(
        id: id,
        direction: CallDirection.outgoing,
        state: CallState.dialling,
        remoteNumber: number,
        startedAt: _clock(),
        muted: _muted,
      ),
    );
    _logLine(
      'call $id to ${_mask(number)}${callerId == null ? '' : ' as ${_mask(callerId)}'}',
    );
    final script = outgoing;
    if (script.ringAfter != null) {
      _after(script.ringAfter!, () {
        if (_active[id]?.state != CallState.dialling) return;
        remoteRinging(id);
        if (script.answerAfter != null) {
          _after(script.answerAfter!, () {
            if (_active[id]?.state != CallState.ringing) return;
            switch (script.outcome) {
              case OutgoingOutcome.answer:
                remoteAnswer(id);
              case OutgoingOutcome.busy:
                _end(id, EndReason.busy);
              case OutgoingOutcome.noAnswer:
                _end(id, EndReason.noAnswer);
              case OutgoingOutcome.failed:
                _end(id, EndReason.failed);
            }
          });
        }
      });
    }
    return id;
  }

  @override
  Future<void> answer(String callId) async {
    final c = _call(callId);
    _requireState(c, {CallState.incoming}, 'answer');
    if (!microphoneGranted) throw const MicrophoneDenied();
    _connect(c);
  }

  @override
  Future<void> decline(String callId) async {
    final c = _call(callId);
    _requireState(c, {CallState.incoming}, 'decline');
    _end(callId, EndReason.declined);
  }

  @override
  Future<void> toVoicemail(String callId) async {
    final c = _call(callId);
    _requireState(c, {CallState.incoming}, 'send to voicemail');
    _end(callId, EndReason.toVoicemail);
  }

  @override
  Future<void> hangup(String callId) async {
    final c = _call(callId);
    _end(
      c.id,
      c.state == CallState.incoming ? EndReason.declined : EndReason.local,
    );
  }

  @override
  Future<void> hold(String callId) async {
    final c = _call(callId);
    _requireState(c, {CallState.connected}, 'hold');
    _emit(_copy(c, state: CallState.heldByMe));
  }

  @override
  Future<void> resume(String callId) async {
    final c = _call(callId);
    _requireState(c, {CallState.heldByMe}, 'resume');
    _emit(_copy(c, state: CallState.connected));
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    for (final c in _active.values.toList()) {
      _emit(_copy(c, muted: muted));
    }
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    final c = _call(callId);
    _requireState(c, {CallState.connected}, 'send DTMF');
    if (!RegExp(r'^[0-9*#A-D]+$').hasMatch(digits)) {
      throw InvalidState('Not DTMF digits: $digits');
    }
    dtmfSent[callId] = (dtmfSent[callId] ?? '') + digits;
  }

  @override
  Future<void> transferBlind(String callId, String target) async {
    final c = _call(callId);
    _requireState(c, {CallState.connected, CallState.heldByMe}, 'transfer');
    transferredTo[callId] = target;
    _emit(_copy(c, state: CallState.transferring));
    _end(callId, EndReason.local);
  }

  @override
  Future<void> transferAttended(String callId, String consultCallId) async {
    final c = _call(callId);
    final consult = _call(consultCallId);
    _requireState(c, {
      CallState.heldByMe,
    }, 'transfer (the first call must be on hold)');
    _requireState(consult, {
      CallState.connected,
    }, 'transfer (the consult call must be connected)');
    transferredTo[callId] = consult.remoteNumber;
    _emit(_copy(c, state: CallState.transferring));
    _end(consultCallId, EndReason.local);
    _end(callId, EndReason.local);
  }

  @override
  Future<void> merge(String callIdA, String callIdB) async {
    final a = _call(callIdA);
    final b = _call(callIdB);
    const ok = {CallState.connected, CallState.heldByMe};
    _requireState(a, ok, 'merge');
    _requireState(b, ok, 'merge');
    merged.addAll([a.id, b.id]);
    if (a.state != CallState.connected) {
      _emit(_copy(a, state: CallState.connected));
    }
    if (b.state != CallState.connected) {
      _emit(_copy(b, state: CallState.connected));
    }
  }

  @override
  Future<void> setAudioRoute(AudioRoute route) async {
    if (!_audioState.available.contains(route)) {
      throw InvalidState('Audio route $route is not available');
    }
    _setAudio(AudioState(route: route, available: _audioState.available));
  }

  @override
  Future<Uint8List> exportLastCallLog() async {
    // Already scrubbed: numbers are masked as they are logged, and the
    // account's password is never written.
    return Uint8List.fromList(utf8.encode('${_log.join('\n')}\n'));
  }

  // ------------------------------------------------------ scripting hooks

  /// The platform rings this device. Returns the call id.
  String simulateIncoming({
    required String remoteNumber,
    String? remoteName,
    IncomingInfo? info,
  }) {
    final id = _newId();
    _emit(
      CallSnapshot(
        id: id,
        direction: CallDirection.incoming,
        state: CallState.incoming,
        remoteNumber: remoteNumber,
        remoteName: remoteName,
        startedAt: _clock(),
        muted: _muted,
        incoming: info,
      ),
    );
    _logLine('incoming $id from ${_mask(remoteNumber)}');
    return id;
  }

  /// Outgoing call reached the far end's phone (180/183).
  void remoteRinging(String callId) {
    final c = _call(callId);
    _requireState(c, {CallState.dialling}, 'ring');
    _emit(_copy(c, state: CallState.ringing));
  }

  /// The far end picked up an outgoing call.
  void remoteAnswer(String callId) {
    final c = _call(callId);
    _requireState(c, {
      CallState.dialling,
      CallState.ringing,
    }, 'answer remotely');
    _connect(c);
  }

  /// The far end hung up, or an incoming caller gave up.
  void remoteHangup(String callId) => _end(callId, EndReason.remote);

  /// The far end ended with a reason: busy, noAnswer, failed, networkLost.
  void remoteEnd(String callId, EndReason reason) => _end(callId, reason);

  /// Another device answered first (CANCEL, "Call completed elsewhere").
  void simulateAnsweredElsewhere(String callId) {
    final c = _call(callId);
    _requireState(c, {CallState.incoming}, 'be answered elsewhere');
    _end(callId, EndReason.answeredElsewhere);
  }

  void remoteHold(String callId) {
    final c = _call(callId);
    _requireState(c, {CallState.connected}, 'be held');
    _emit(_copy(c, state: CallState.heldByRemote));
  }

  void remoteResume(String callId) {
    final c = _call(callId);
    _requireState(c, {CallState.heldByRemote}, 'be resumed');
    _emit(_copy(c, state: CallState.connected));
  }

  /// The next register() ends in [failure] instead of ok.
  void failNextRegistration(RegistrationFailure failure, {int? sipCode}) {
    _failNext = failure;
    _failNextCode = sipCode;
  }

  /// The network dropped: registration fails and every call ends.
  void simulateNetworkLost() {
    for (final id in _active.keys.toList()) {
      _end(id, EndReason.networkLost);
    }
    _setReg(
      const RegistrationEvent(
        RegistrationState.failed,
        failure: RegistrationFailure.network,
      ),
    );
  }

  /// Bluetooth or a wired headset came or went.
  void simulateAudioDevices(Set<AudioRoute> available, {AudioRoute? route}) {
    final next =
        route ??
        (available.contains(_audioState.route)
            ? _audioState.route
            : AudioRoute.earpiece);
    _setAudio(
      AudioState(route: next, available: {...available, AudioRoute.earpiece}),
    );
  }

  /// Level the waveform shows for a tick; overrides the built-in pattern.
  double Function(int tick)? levelPattern;

  Future<void> dispose() async {
    _cancelTimers();
    // Not awaited: a paused listener (a provider nobody watches) would hold
    // the close futures open.
    for (final c in [_registration, _calls, _audio, _level]) {
      unawaited(c.close());
    }
  }

  // ------------------------------------------------------------- internal

  void _connect(CallSnapshot c) {
    _emit(
      _copy(
        c,
        state: CallState.connected,
        connectedAt: _clock(),
        encrypted: encrypted,
        hdAudio: hdAudio,
      ),
    );
    _logLine('connected ${c.id}');
  }

  void _end(String callId, EndReason reason) {
    final c = _call(callId);
    _active.remove(callId);
    merged.remove(callId);
    final ended = _copy(c, state: CallState.ended, endReason: reason);
    _calls.add(ended);
    _logLine('ended ${c.id} ${reason.name}');
    _updateLevelTimer();
  }

  void _emit(CallSnapshot s) {
    _active[s.id] = s;
    _calls.add(s);
    _updateLevelTimer();
  }

  void _updateLevelTimer() {
    final connected = _active.values.any((c) => c.state == CallState.connected);
    if (connected && _levelTimer == null) {
      _levelTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final tick = _levelTick++;
        final muted = _muted;
        final v = muted
            ? 0.0
            : (levelPattern ?? _defaultLevel)(tick).clamp(0.0, 1.0);
        _level.add(v);
      });
    } else if (!connected && _levelTimer != null) {
      _levelTimer!.cancel();
      _levelTimer = null;
    }
  }

  static double _defaultLevel(int tick) {
    // Speech-like: a slow envelope times a faster wobble, 0..1.
    final env = 0.5 + 0.5 * math.sin(tick / 9);
    final wob = 0.6 + 0.4 * math.sin(tick * 1.7);
    return env * wob;
  }

  CallSnapshot _call(String id) => _active[id] ?? (throw NoSuchCall(id));

  void _requireState(CallSnapshot c, Set<CallState> allowed, String action) {
    if (!allowed.contains(c.state)) {
      throw InvalidState('Cannot $action call ${c.id} while ${c.state.name}');
    }
  }

  void _requireStarted() {
    if (!_started) throw const InvalidState('Engine not started');
  }

  void _setReg(RegistrationEvent e) {
    _regState = e.state;
    _registration.add(e);
  }

  void _setAudio(AudioState s) {
    _audioState = s;
    _audio.add(s);
  }

  void _after(Duration d, void Function() f) {
    late final Timer t;
    t = Timer(d, () {
      _timers.remove(t);
      f();
    });
    _timers.add(t);
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _levelTimer?.cancel();
    _levelTimer = null;
  }

  String _newId() => 'fake-${_nextId++}';

  void _logLine(String s) {
    _log.add('${_clock().toUtc().toIso8601String()} $s');
    if (_log.length > 500) _log.removeAt(0);
  }

  /// Keeps the last three digits only, as the real log scrubber does (APP9).
  static String _mask(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return number;
    return '${'*' * (digits.length - 3)}${digits.substring(digits.length - 3)}';
  }

  static CallSnapshot _copy(
    CallSnapshot c, {
    CallState? state,
    DateTime? connectedAt,
    bool? muted,
    bool? encrypted,
    bool? hdAudio,
    EndReason? endReason,
  }) => CallSnapshot(
    id: c.id,
    direction: c.direction,
    state: state ?? c.state,
    remoteNumber: c.remoteNumber,
    remoteName: c.remoteName,
    startedAt: c.startedAt,
    connectedAt: connectedAt ?? c.connectedAt,
    muted: muted ?? c.muted,
    encrypted: encrypted ?? c.encrypted,
    hdAudio: hdAudio ?? c.hdAudio,
    incoming: c.incoming,
    endReason: endReason ?? c.endReason,
  );
}
