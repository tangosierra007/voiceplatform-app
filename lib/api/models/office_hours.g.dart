// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'office_hours.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OfficeHours _$OfficeHoursFromJson(Map<String, dynamic> json) => OfficeHours(
  id: json['id'] as String,
  name: json['name'] as String,
  mode: OfficeHoursMode.fromJson(json['mode'] as String),
  openNow: json['openNow'] as bool,
  until: json['until'] == null ? null : DateTime.parse(json['until'] as String),
  summary: json['summary'] as String?,
);

Map<String, dynamic> _$OfficeHoursToJson(OfficeHours instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'mode': instance.mode,
      'openNow': instance.openNow,
      'until': instance.until?.toIso8601String(),
      'summary': instance.summary,
    };
