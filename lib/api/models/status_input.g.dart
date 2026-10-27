// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StatusInput _$StatusInputFromJson(Map<String, dynamic> json) => StatusInput(
  status: StatusInputStatus.fromJson(json['status'] as String),
  dndUntil: json['dndUntil'] == null
      ? null
      : DateTime.parse(json['dndUntil'] as String),
);

Map<String, dynamic> _$StatusInputToJson(StatusInput instance) =>
    <String, dynamic>{
      'status': instance.status.toJson(),
      'dndUntil': ?instance.dndUntil?.toIso8601String(),
    };
