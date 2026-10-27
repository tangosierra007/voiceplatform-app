// Pigeon definition of the typed channel between the Dart engine
// (VpLinphoneEngine) and the Kotlin side (one liblinphone Core in a
// foreground service). Regenerate with:
//
//   dart run pigeon --input pigeons/messages.dart
//
// The generated files are committed; never edit them by hand.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/au/com/voiceplatform/vp_linphone/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'au.com.voiceplatform.vp_linphone', errorClassName: 'VpFlutterError'),
    copyrightHeader: 'pigeons/copyright.txt',
    dartPackageName: 'vp_linphone',
  ),
)
enum RegStateMsg { none, progress, ok, cleared, failed }

enum RegFailureMsg { badCredentials, forbidden, network, tls, timeout, unknown }

class RegistrationMsg {
  RegistrationMsg({required this.state});
  RegStateMsg state;
  RegFailureMsg? failure;
  int? sipCode;
}

enum CallStateMsg { dialling, ringing, incoming, connected, heldByMe, heldByRemote, transferring, ended }

enum EndReasonMsg { local, remote, declined, busy, noAnswer, answeredElsewhere, toVoicemail, networkLost, failed }

enum AudioRouteMsg { earpiece, speaker, bluetooth, wiredHeadset, car }

/// One call as the Kotlin side sees it. The X-VP-* header values are passed
/// raw and parsed on the Dart side (IncomingHeaders).
class CallMsg {
  CallMsg({
    required this.id,
    required this.incoming,
    required this.state,
    required this.remoteNumber,
    required this.muted,
    required this.encrypted,
    required this.hdAudio,
  });
  String id;
  bool incoming;
  CallStateMsg state;
  String remoteNumber;
  String? remoteName;
  int? startedAtMs;
  int? connectedAtMs;
  bool muted;
  bool encrypted;
  bool hdAudio;
  EndReasonMsg? endReason;
  String? headerCalled;
  String? headerAlsoRinging;
  String? headerRepeat;
  String? headerLastAnswered;
}

class AudioMsg {
  AudioMsg({required this.route, required this.available});
  AudioRouteMsg route;
  List<AudioRouteMsg> available;
}

/// The contract's PushMessage types (app-api.openapi.yaml). Only the four the
/// app handles reach Dart; incoming_call and call_cancelled are native.
enum PushTypeMsg { incomingCall, callCancelled, voicemail, message, signedOut, config }

class PushMsg {
  PushMsg({required this.type, required this.pushId});
  PushTypeMsg type;
  String pushId;
  String? sentAt;
}

enum UiRequestKindMsg { showIncoming, showCall }

/// Asks the app (WS4) to show a screen: from a notification tap, the
/// full-screen intent on a locked phone, or an answer from the notification.
class UiRequestMsg {
  UiRequestMsg({required this.kind, required this.callId});
  UiRequestKindMsg kind;
  String callId;
}

/// Per-call audio quality from liblinphone's RTCP statistics (MOS hooks for
/// v1.x; nothing sends them yet).
class QualityMsg {
  QualityMsg({
    required this.callId,
    required this.jitterMs,
    required this.localLossPercent,
    required this.remoteLossPercent,
    required this.roundTripMs,
  });
  String callId;

  /// liblinphone's quality estimate, 0 (worst) to 5 (best), MOS-like; null
  /// until it has one.
  double? quality;
  double jitterMs;
  double localLossPercent;
  double remoteLossPercent;
  double roundTripMs;
}

class BatteryMsg {
  BatteryMsg({required this.ignoringOptimizations, required this.lateWakesLastWeek, required this.manufacturer});
  bool ignoringOptimizations;
  int lateWakesLastWeek;
  String manufacturer;
}

/// Dart to Kotlin. Errors come back as PlatformException with one of the codes
/// `not_registered`, `microphone_denied`, `no_such_call`, `invalid_state`.
@HostApi()
abstract class VpLinphoneHostApi {
  @async
  void start();

  @async
  void stop();

  /// The password crosses the channel once, here, and is never sent back.
  void register(
    String authUsername,
    String password,
    String domain,
    String outboundProxy,
    String displayName,
    int expiresSeconds,
    String instanceId,
    String? pushProvider,
    String? pushPrid,
    String? pushParam,
  );

  @async
  void unregister();

  void updatePush(String provider, String prid, String param);

  String call(String number, String? callerId);
  void answer(String callId);
  void decline(String callId);

  /// 302 to `sip:<voicemailUser>@<domain>`.
  void toVoicemail(String callId, String voicemailUser);
  void hangup(String callId);
  void hold(String callId);
  void resume(String callId);
  void setMuted(bool muted);
  void sendDtmf(String callId, String digits);
  void transferBlind(String callId, String target);
  void transferAttended(String callId, String consultCallId);
  void merge(String callIdA, String callIdB);
  void setAudioRoute(AudioRouteMsg route);

  @async
  Uint8List exportLastCallLog();

  /// Re-sends the current registration, calls and audio state (a Flutter
  /// engine attaching after a push woke the engine natively).
  void syncState();

  /// Pushes that arrived while no Flutter engine was attached (types only).
  List<PushMsg> takePendingPushes();

  /// The UI request the activity was launched with, once.
  UiRequestMsg? takeUiRequest();

  BatteryMsg batteryStatus();
  void openBatteryOptimizationSettings();

  /// Android 14+: whether the full-screen incoming-call UI is allowed.
  bool canUseFullScreenIntent();
  void openFullScreenIntentSettings();
}

/// Kotlin to Dart events.
@FlutterApi()
abstract class VpLinphoneEventsApi {
  void onRegistration(RegistrationMsg event);
  void onCall(CallMsg call);
  void onAudio(AudioMsg audio);

  /// Microphone level of the active call in dBm0 (liblinphone's record volume).
  void onInputLevel(double dbm0);

  void onPush(PushMsg push);
  void onUiRequest(UiRequestMsg request);

  /// An incoming call was shown as a heads-up notification because the
  /// full-screen intent is not allowed (Android 14+).
  void onFullScreenIntentDenied(String callId);

  /// Every 2 s while a call is connected.
  void onCallQuality(QualityMsg quality);
}
