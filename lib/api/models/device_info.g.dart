// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
  platform: Platform.fromJson(json['platform'] as String),
  model: json['model'] as String,
  appVersion: json['appVersion'] as String,
  osVersion: json['osVersion'] as String?,
);

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'platform': instance.platform.toJson(),
      'model': instance.model,
      'osVersion': ?instance.osVersion,
      'appVersion': instance.appVersion,
    };
