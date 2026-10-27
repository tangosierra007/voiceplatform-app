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
  void toVoicemail(String callId);
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
}

/// Kotlin to Dart events.
@FlutterApi()
abstract class VpLinphoneEventsApi {
  void onRegistration(RegistrationMsg event);
  void onCall(CallMsg call);
  void onAudio(AudioMsg audio);

  /// Microphone level of the active call in dBm0 (liblinphone's record volume).
  void onInputLevel(double dbm0);
}
