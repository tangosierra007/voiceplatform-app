// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PushMessage _$PushMessageFromJson(Map<String, dynamic> json) => PushMessage(
  type: PushMessageType.fromJson(json['type'] as String),
  pushId: json['pushId'] as String,
  sentAt: json['sentAt'] == null
      ? null
      : DateTime.parse(json['sentAt'] as String),
);

Map<String, dynamic> _$PushMessageToJson(PushMessage instance) =>
    <String, dynamic>{
      'type': instance.type,
      'pushId': instance.pushId,
      'sentAt': instance.sentAt?.toIso8601String(),
    };
