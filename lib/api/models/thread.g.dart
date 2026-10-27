// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Thread _$ThreadFromJson(Map<String, dynamic> json) => Thread(
  id: json['id'] as String,
  lineId: json['lineId'] as String,
  lineLabel: json['lineLabel'] as String,
  number: json['number'] as String,
  lastAt: DateTime.parse(json['lastAt'] as String),
  lastText: json['lastText'] as String,
  unread: (json['unread'] as num).toInt(),
  name: json['name'] as String?,
  channel: json['channel'] == null
      ? null
      : ThreadChannel.fromJson(json['channel'] as String),
);

Map<String, dynamic> _$ThreadToJson(Thread instance) => <String, dynamic>{
  'id': instance.id,
  'lineId': instance.lineId,
  'lineLabel': instance.lineLabel,
  'number': instance.number,
  'name': instance.name,
  'lastAt': instance.lastAt.toIso8601String(),
  'lastText': instance.lastText,
  'unread': instance.unread,
  'channel': instance.channel,
};
