// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voicemail_box.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VoicemailBox _$VoicemailBoxFromJson(Map<String, dynamic> json) => VoicemailBox(
  id: json['id'] as String,
  name: json['name'] as String,
  kind: VoicemailBoxKind.fromJson(json['kind'] as String),
  newCount: (json['newCount'] as num).toInt(),
  totalCount: (json['totalCount'] as num).toInt(),
);

Map<String, dynamic> _$VoicemailBoxToJson(VoicemailBox instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'kind': instance.kind.toJson(),
      'newCount': instance.newCount,
      'totalCount': instance.totalCount,
    };
