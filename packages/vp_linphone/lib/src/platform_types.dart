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
