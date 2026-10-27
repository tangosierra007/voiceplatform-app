// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'colleague.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Colleague _$ColleagueFromJson(Map<String, dynamic> json) => Colleague(
  userId: json['userId'] as String,
  name: json['name'] as String,
  initials: json['initials'] as String,
  extensionValue: json['extension'] as String,
  presence: PresenceEntry.fromJson(json['presence'] as Map<String, dynamic>),
  team: json['team'] as String?,
  role: json['role'] as String?,
  mobile: json['mobile'] as String?,
);

Map<String, dynamic> _$ColleagueToJson(Colleague instance) => <String, dynamic>{
  'userId': instance.userId,
  'name': instance.name,
  'initials': instance.initials,
  'extension': instance.extensionValue,
  'team': ?instance.team,
  'role': ?instance.role,
  'mobile': ?instance.mobile,
  'presence': instance.presence.toJson(),
};
