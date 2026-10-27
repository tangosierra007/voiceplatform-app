// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Session _$SessionFromJson(Map<String, dynamic> json) => Session(
  accessToken: json['accessToken'] as String,
  accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String),
  refreshToken: json['refreshToken'] as String,
  refreshExpiresAt: DateTime.parse(json['refreshExpiresAt'] as String),
  deviceId: json['deviceId'] as String,
  me: Me.fromJson(json['me'] as Map<String, dynamic>),
);

Map<String, dynamic> _$SessionToJson(Session instance) => <String, dynamic>{
  'accessToken': instance.accessToken,
  'accessExpiresAt': instance.accessExpiresAt.toIso8601String(),
  'refreshToken': instance.refreshToken,
  'refreshExpiresAt': instance.refreshExpiresAt.toIso8601String(),
  'deviceId': instance.deviceId,
  'me': instance.me,
};
