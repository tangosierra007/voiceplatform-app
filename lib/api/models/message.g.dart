// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  id: json['id'] as String,
  threadId: json['threadId'] as String,
  direction: MessageDirection.fromJson(json['direction'] as String),
  at: DateTime.parse(json['at'] as String),
  kind: MessageKind.fromJson(json['kind'] as String),
  status: MessageStatus.fromJson(json['status'] as String),
  text: json['text'] as String?,
  senderName: json['senderName'] as String?,
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'id': instance.id,
  'threadId': instance.threadId,
  'direction': instance.direction.toJson(),
  'at': instance.at.toIso8601String(),
  'kind': instance.kind.toJson(),
  'text': ?instance.text,
  'senderName': ?instance.senderName,
  'status': instance.status.toJson(),
};
