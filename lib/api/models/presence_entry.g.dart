// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presence_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PresenceEntry _$PresenceEntryFromJson(Map<String, dynamic> json) =>
    PresenceEntry(
      extensionValue: json['extension'] as String,
      presence: Presence.fromJson(json['presence'] as String),
      since: json['since'] == null
          ? null
          : DateTime.parse(json['since'] as String),
      dndUntil: json['dndUntil'] == null
          ? null
          : DateTime.parse(json['dndUntil'] as String),
      detail: json['detail'] as String?,
    );

Map<String, dynamic> _$PresenceEntryToJson(PresenceEntry instance) =>
    <String, dynamic>{
      'extension': instance.extensionValue,
      'presence': instance.presence.toJson(),
      'since': ?instance.since?.toIso8601String(),
      'dndUntil': ?instance.dndUntil?.toIso8601String(),
      'detail': ?instance.detail,
    };
