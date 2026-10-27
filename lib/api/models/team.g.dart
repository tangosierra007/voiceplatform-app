// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Team _$TeamFromJson(Map<String, dynamic> json) => Team(
  id: json['id'] as String,
  name: json['name'] as String,
  memberCount: (json['memberCount'] as num).toInt(),
  freeCount: (json['freeCount'] as num).toInt(),
  members: (json['members'] as List<dynamic>).map((e) => e as String).toList(),
  number: json['number'] as String?,
  ringOrder: json['ringOrder'] == null
      ? null
      : TeamRingOrder.fromJson(json['ringOrder'] as String),
);

Map<String, dynamic> _$TeamToJson(Team instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'number': instance.number,
  'memberCount': instance.memberCount,
  'freeCount': instance.freeCount,
  'ringOrder': instance.ringOrder,
  'members': instance.members,
};
