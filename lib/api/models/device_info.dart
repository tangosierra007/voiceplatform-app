// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'platform.dart';

part 'device_info.g.dart';

@JsonSerializable()
class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    required this.model,
    required this.appVersion,
    this.osVersion,
  });
  
  factory DeviceInfo.fromJson(Map<String, Object?> json) => _$DeviceInfoFromJson(json);
  
  final Platform platform;
  final String model;
  final String? osVersion;
  final String appVersion;

  Map<String, Object?> toJson() => _$DeviceInfoToJson(this);
}
