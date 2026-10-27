// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tokens.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Tokens _$TokensFromJson(Map<String, dynamic> json) => Tokens(
  accessToken: json['accessToken'] as String,
  accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String),
  refreshToken: json['refreshToken'] as String,
  refreshExpiresAt: DateTime.parse(json['refreshExpiresAt'] as String),
);

Map<String, dynamic> _$TokensToJson(Tokens instance) => <String, dynamic>{
  'accessToken': instance.accessToken,
  'accessExpiresAt': instance.accessExpiresAt.toIso8601String(),
  'refreshToken': instance.refreshToken,
  'refreshExpiresAt': instance.refreshExpiresAt.toIso8601String(),
};
