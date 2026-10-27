// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'counts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Counts _$CountsFromJson(Map<String, dynamic> json) => Counts(
  missed: (json['missed'] as num).toInt(),
  voicemail: (json['voicemail'] as num).toInt(),
);

Map<String, dynamic> _$CountsToJson(Counts instance) => <String, dynamic>{
  'missed': instance.missed,
  'voicemail': instance.voicemail,
};
