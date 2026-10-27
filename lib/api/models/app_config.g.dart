// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => AppConfig(
  platform: Platform.fromJson(json['platform'] as String),
  minimumVersion: json['minimumVersion'] as String,
  recommendedVersion: json['recommendedVersion'] as String,
  storeUrl: json['storeUrl'] as String,
);

Map<String, dynamic> _$AppConfigToJson(AppConfig instance) => <String, dynamic>{
  'platform': instance.platform,
  'minimumVersion': instance.minimumVersion,
  'recommendedVersion': instance.recommendedVersion,
  'storeUrl': instance.storeUrl,
};
