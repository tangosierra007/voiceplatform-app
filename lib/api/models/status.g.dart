// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Status _$StatusFromJson(Map<String, dynamic> json) => Status(
  status: StatusStatus.fromJson(json['status'] as String),
  dndUntil: json['dndUntil'] == null
      ? null
      : DateTime.parse(json['dndUntil'] as String),
  changedAt: json['changedAt'] == null
      ? null
      : DateTime.parse(json['changedAt'] as String),
);

Map<String, dynamic> _$StatusToJson(Status instance) => <String, dynamic>{
  'status': instance.status.toJson(),
  'dndUntil': ?instance.dndUntil?.toIso8601String(),
  'changedAt': ?instance.changedAt?.toIso8601String(),
};
