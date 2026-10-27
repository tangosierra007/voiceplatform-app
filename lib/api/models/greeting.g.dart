// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'greeting.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Greeting _$GreetingFromJson(Map<String, dynamic> json) => Greeting(
  kind: GreetingKind.fromJson(json['kind'] as String),
  isCustom: json['isCustom'] as bool,
  durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$GreetingToJson(Greeting instance) => <String, dynamic>{
  'kind': instance.kind.toJson(),
  'isCustom': instance.isCustom,
  'durationSeconds': ?instance.durationSeconds,
  'updatedAt': ?instance.updatedAt?.toIso8601String(),
};
