// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'permissions.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Permissions _$PermissionsFromJson(Map<String, dynamic> json) => Permissions(
  recordings: json['recordings'] as bool,
  officeHours: json['officeHours'] as bool,
  messages: json['messages'] as bool,
  sharedVoicemail: json['sharedVoicemail'] as bool,
);

Map<String, dynamic> _$PermissionsToJson(Permissions instance) =>
    <String, dynamic>{
      'recordings': instance.recordings,
      'officeHours': instance.officeHours,
      'messages': instance.messages,
      'sharedVoicemail': instance.sharedVoicemail,
    };
