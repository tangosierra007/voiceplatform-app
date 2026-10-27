// CallEngine: the seam between the app's UI (WS4) and the SIP engine (WS3).
//
// Contract owned by mobile-lead (spec 22, section "Call engine"). WS4 builds
// against FakeCallEngine; WS3 implements it in packages/vp_linphone on top of
// liblinphone. A change to this file goes through the lead only.
//
// Rules every implementation keeps:
// - SIP credentials go in through register() and are never readable back,
//   never logged and never part of any event (APP4).
// - The UI hands emergency numbers to the phone's dialler first (APP6). call()
//   never refuses one: if it gets here it is placed, and the platform routes it
//   like any emergency call and raises an alert (CLAUDE.md rule 8, decision 139).
// - Nothing here touches the network except SIP and RTP to the platform edge.
// - Platform-neutral: no Android or iOS type crosses this interface.

import 'dart:async';
import 'dart:typed_data';

/// Where the engine registers. Built from POST /app/v1/devices/me/sip-credentials;
/// held in memory and the platform keystore only.
final class SipAccount {
  const SipAccount({
    required this.authUsername,
    required this.password,
    required this.domain,
    required this.outboundProxy,
    required this.displayName,
    required this.expiresSeconds,
    this.push,
  });

  /// Per-device auth username (spec 22, Device model). Not the extension's.
  final String authUsername;

  /// Never logged, never in an event, never returned by any getter.
  final String password;

  /// Tenant SIP domain, for example `democo.sip.voiceplatform.com.au`.
  final String domain;

  /// `sip:sip.voiceplatform.com.au:5061;transport=tls` (plain sip: over TLS, decision 70).
  final String outboundProxy;
  final String displayName;
  final int expiresSeconds;

  /// RFC 8599 contact parameters; null on desktop (no push).
  final PushParams? push;

  @override
  String toString() => 'SipAccount($authUsername@$domain)';
}

/// RFC 8599 contact parameters. Android: provider `fcm`, prid the FCM token,
/// param `voiceplatform-app`. iOS later: `apns`.
final class PushParams {
  const PushParams({required this.provider, required this.prid, required this.param});
  final String provider;
  final String prid;
  final String param;
}

enum RegistrationState { none, progress, ok, cleared, failed }

/// Why registration failed, mapped to what the UI shows.
enum RegistrationFailure { badCredentials, forbidden, network, tls, timeout, unknown }

final class RegistrationEvent {
  const RegistrationEvent(this.state, {this.failure, this.sipCode});
  final RegistrationState state;
  final RegistrationFailure? failure;
  final int? sipCode;
}

enum CallDirection { incoming, outgoing }

enum CallState {
  /// Outgoing: INVITE sent, no answer yet.
  dialling,

  /// Outgoing: 180 or 183 received.
  ringing,

  /// Incoming: ringing on this device.
  incoming,
  connected,
  heldByMe,
  heldByRemote,

  /// Attended transfer in progress from this call.
  transferring,
  ended,
}

enum EndReason {
  local,
  remote,
  declined,
  busy,
  noAnswer,

  /// Answered on another device (SIP CANCEL with Reason "Call completed elsewhere").
  answeredElsewhere,

  /// Sent to voicemail by this device.
  toVoicemail,
  networkLost,
  failed,
}

enum AudioRoute { earpiece, speaker, bluetooth, wiredHeadset, car }

/// Facts the platform puts in SIP headers for the incoming screen (A7, B27).
/// Same fields as the push payload; never more than the screen shows (APP5).
final class IncomingInfo {
  const IncomingInfo({
    this.calledNumber,
    this.calledLabel,
    this.alsoRinging = const [],
    this.repeatCount,
    this.lastAnsweredBy,
    this.lastAnsweredAt,
  });

  /// E.164 of the number or group dialled, for example `+61355501201`.
  final String? calledNumber;

  /// `Sales`, `Sales group`.
  final String? calledLabel;

  /// Display strings, for example `Mia's desk phone`.
  final List<String> alsoRinging;

  /// Calls from this number this week including this one (3 shows "3rd call this week").
  final int? repeatCount;
  final String? lastAnsweredBy;
  final DateTime? lastAnsweredAt;
}

final class CallSnapshot {
  const CallSnapshot({
    required this.id,
    required this.direction,
    required this.state,
    required this.remoteNumber,
    this.remoteName,
    this.startedAt,
    this.connectedAt,
    this.muted = false,
    this.encrypted = false,
    this.hdAudio = false,
    this.incoming,
    this.endReason,
  });

  /// Engine-local call id, stable for the life of the call.
  final String id;
  final CallDirection direction;
  final CallState state;

  /// As the platform sent it; `anonymous` for withheld.
  final String remoteNumber;
  final String? remoteName;
  final DateTime? startedAt;
  final DateTime? connectedAt;
  final bool muted;

  /// True when TLS signalling and SRTP media are both in use.
  final bool encrypted;

  /// True for a wideband codec (Opus, G.722). App devices offer Opus first
  /// (decision 135).
  final bool hdAudio;
  final IncomingInfo? incoming;
  final EndReason? endReason;
}

/// Engine-wide audio facts for the in-call screen.
final class AudioState {
  const AudioState({required this.route, required this.available});
  final AudioRoute route;
  final Set<AudioRoute> available;
}

sealed class CallEngineError implements Exception {
  const CallEngineError(this.message);
  final String message;
}

final class NotRegistered extends CallEngineError {
  const NotRegistered() : super('Not registered');
}

final class MicrophoneDenied extends CallEngineError {
  const MicrophoneDenied() : super('Microphone permission not granted');
}

final class NoSuchCall extends CallEngineError {
  const NoSuchCall(String id) : super('No call $id');
}

final class InvalidState extends CallEngineError {
  const InvalidState(super.message);
}

abstract interface class CallEngine {
  /// Starts the engine (Android: the foreground service and one liblinphone Core).
  Future<void> start();
  Future<void> stop();

  /// Registers with the given account; replaces any earlier one.
  Future<void> register(SipAccount account);

  /// Unregisters and forgets the account (sign-out, revoke, update required).
  Future<void> unregister();

  /// Refreshes the RFC 8599 params after an FCM token change, without dropping calls.
  Future<void> updatePush(PushParams push);
  Stream<RegistrationEvent> get registration;

  /// Places a call. [callerId] is an E.164 from GET /app/v1/me/caller-ids or
  /// `withheld`; null uses the extension default. Sent as the X-VP-Caller-Id
  /// header, which the platform checks against the tenant's numbers.
  Future<String> call(String number, {String? callerId});
  Future<void> answer(String callId);

  /// Decline: 486 for this device only; other devices keep ringing.
  Future<void> decline(String callId);

  /// "To voicemail": 302 to the extension's voicemail (A5).
  Future<void> toVoicemail(String callId);
  Future<void> hangup(String callId);
  Future<void> hold(String callId);
  Future<void> resume(String callId);
  Future<void> setMuted(bool muted);
  Future<void> sendDtmf(String callId, String digits);

  /// Blind transfer (REFER) to [target], an extension or number.
  Future<void> transferBlind(String callId, String target);

  /// Attended transfer: [callId] is on hold, [consultCallId] is the call to the
  /// colleague; REFER with Replaces joins them.
  Future<void> transferAttended(String callId, String consultCallId);

  /// Local 3-way: mixes both calls on this device.
  Future<void> merge(String callIdA, String callIdB);
  Future<void> setAudioRoute(AudioRoute route);
  Stream<AudioState> get audio;

  /// Every change to any call, latest snapshot per call.
  Stream<CallSnapshot> get calls;
  List<CallSnapshot> get activeCalls;

  /// Input level 0..1 at about 20 Hz while a call is connected, for the waveform.
  Stream<double> get inputLevel;

  /// The rotating log for the most recent call, already scrubbed of passwords,
  /// tokens and full numbers (APP9), for "Send call logs to support".
  Future<Uint8List> exportLastCallLog();
}
