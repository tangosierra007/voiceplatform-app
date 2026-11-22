// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'desk.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Desk _$DeskFromJson(Map<String, dynamic> json) => Desk(
  extensionId: json['extensionId'] as String,
  extensionValue: json['extension'] as String,
  name: json['name'] as String,
  initials: json['initials'] as String,
  presence: PresenceEntry.fromJson(json['presence'] as Map<String, dynamic>),
  team: json['team'] as String?,
);

Map<String, dynamic> _$DeskToJson(Desk instance) => <String, dynamic>{
  'extensionId': instance.extensionId,
  'extension': instance.extensionValue,
  'name': instance.name,
  'initials': instance.initials,
  'team': ?instance.team,
  'presence': instance.presence.toJson(),
};
