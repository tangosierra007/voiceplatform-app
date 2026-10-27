// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'licence_refusal.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LicenceRefusal _$LicenceRefusalFromJson(Map<String, dynamic> json) =>
    LicenceRefusal(
      error: LicenceRefusalError.fromJson(json['error'] as String),
      message: json['message'] as String,
      extensionValue: json['extension'] as String?,
      extensionName: json['extensionName'] as String?,
      refusalToken: json['refusalToken'] as String?,
    );

Map<String, dynamic> _$LicenceRefusalToJson(LicenceRefusal instance) =>
    <String, dynamic>{
      'error': instance.error.toJson(),
      'message': instance.message,
      'extension': ?instance.extensionValue,
      'extensionName': ?instance.extensionName,
      'refusalToken': ?instance.refusalToken,
    };
