// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signed_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SignedOut _$SignedOutFromJson(Map<String, dynamic> json) => SignedOut(
  error: SignedOutError.fromJson(json['error'] as String),
  message: json['message'] as String,
  revokedBy: json['revokedBy'] as String?,
  revokedAt: json['revokedAt'] == null
      ? null
      : DateTime.parse(json['revokedAt'] as String),
  extensionValue: json['extension'] as String?,
  support: json['support'] == null
      ? null
      : Support.fromJson(json['support'] as Map<String, dynamic>),
);

Map<String, dynamic> _$SignedOutToJson(SignedOut instance) => <String, dynamic>{
  'error': instance.error,
  'message': instance.message,
  'revokedBy': instance.revokedBy,
  'revokedAt': instance.revokedAt?.toIso8601String(),
  'extension': instance.extensionValue,
  'support': instance.support,
};
