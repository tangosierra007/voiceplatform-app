// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'push_message_type.dart';

part 'push_message.g.dart';

/// FCM data message, high priority, from the push gateway (WS2). Carries no caller or.
/// message content (APP5): the app wakes and fetches. Incoming-call facts come in the SIP.
/// INVITE headers (spec 22, Incoming call path), not the push.
///
@JsonSerializable()
class PushMessage {
  const PushMessage({
    required this.type,
    required this.pushId,
    this.sentAt,
  });
  
  factory PushMessage.fromJson(Map<String, Object?> json) => _$PushMessageFromJson(json);
  
  final PushMessageType type;

  /// Random per push, for de-duplication and the Homer trace
  final String pushId;
  final DateTime? sentAt;

  Map<String, Object?> toJson() => _$PushMessageToJson(this);
}
