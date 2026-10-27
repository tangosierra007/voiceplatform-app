// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Recording _$RecordingFromJson(Map<String, dynamic> json) => Recording(
  id: json['id'] as String,
  at: DateTime.parse(json['at'] as String),
  direction: RecordingDirection.fromJson(json['direction'] as String),
  number: json['number'] as String,
  durationSeconds: (json['durationSeconds'] as num).toInt(),
  name: json['name'] as String?,
);

Map<String, dynamic> _$RecordingToJson(Recording instance) => <String, dynamic>{
  'id': instance.id,
  'at': instance.at.toIso8601String(),
  'direction': instance.direction.toJson(),
  'number': instance.number,
  'name': ?instance.name,
  'durationSeconds': instance.durationSeconds,
};
