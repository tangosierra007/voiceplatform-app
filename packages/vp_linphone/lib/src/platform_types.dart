/// Android-side facts the app (WS4) needs beyond CallEngine: push messages
/// for the app, screen requests from the incoming-call notification, and the
/// battery-optimisation state for the Me card.
library;

/// The contract's PushMessage types that reach the app (app-api.openapi.yaml).
/// `incoming_call` and `call_cancelled` are handled natively and not listed.
enum VpPushType { voicemail, message, signedOut, config }

/// A data push for the app: no caller or content (APP5); the app fetches.
final class VpPushMessage {
  const VpPushMessage(this.type, this.pushId, {this.sentAt});
  final VpPushType type;
  final String pushId;
  final DateTime? sentAt;

  @override
  String toString() => 'VpPushMessage(${type.name}, $pushId)';
}

enum VpUiRequestKind {
  /// Show the incoming-call screen (AppIncoming) for [VpUiRequest.callId]:
  /// the full-screen intent on a locked phone, or a notification tap.
  showIncoming,

  /// The call was answered from the notification: show the in-call screen.
  showCall,
}

final class VpUiRequest {
  const VpUiRequest(this.kind, this.callId);
  final VpUiRequestKind kind;
  final String callId;

  @override
  bool operator ==(Object other) => other is VpUiRequest && other.kind == kind && other.callId == callId;

  @override
  int get hashCode => Object.hash(kind, callId);

  @override
  String toString() => 'VpUiRequest(${kind.name}, $callId)';
}

/// For the Me card "Calls may be missed while this phone saves battery"
/// (spec 22, Battery optimisation; 4.4 decides when to show it).
final class VpBatteryStatus {
  const VpBatteryStatus({
    required this.ignoringOptimizations,
    required this.lateWakesLastWeek,
    required this.manufacturer,
  });

  /// True when the user exempted the app in Android's battery settings.
  final bool ignoringOptimizations;

  /// Push wakes whose registration came after the 8 s budget, last 7 days.
  final int lateWakesLastWeek;

  /// `Build.MANUFACTURER`, for the list of makers known to delay FCM.
  final String manufacturer;
}

/// One sample of a connected call's audio quality from liblinphone's RTCP
/// statistics (MOS hooks for v1.x).
final class VpCallQuality {
  const VpCallQuality({
    required this.callId,
    this.quality,
    required this.jitterMs,
    required this.localLossPercent,
    required this.remoteLossPercent,
    required this.roundTripMs,
  });
  final String callId;

  /// liblinphone's estimate, 0 (worst) to 5 (best), on a MOS-like scale;
  /// null while it has none (never 0 for unknown).
  final double? quality;

  /// Interarrival jitter the far end reported, in milliseconds.
  final double jitterMs;

  /// Packets lost on the way to us, and as the far end reported, in percent.
  final double localLossPercent;
  final double remoteLossPercent;

  /// RTCP round trip, in milliseconds.
  final double roundTripMs;
}
