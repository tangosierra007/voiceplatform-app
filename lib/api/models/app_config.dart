// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'platform.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  const AppConfig({
    required this.platform,
    required this.minimumVersion,
    required this.recommendedVersion,
    required this.storeUrl,
  });
  
  factory AppConfig.fromJson(Map<String, Object?> json) => _$AppConfigFromJson(json);
  
  final Platform platform;
  final String minimumVersion;
  final String recommendedVersion;
  final String storeUrl;

  Map<String, Object?> toJson() => _$AppConfigToJson(this);
}
