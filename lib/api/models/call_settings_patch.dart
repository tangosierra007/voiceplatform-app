// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'call_settings_patch.g.dart';

@JsonSerializable()
class CallSettingsPatch {
  const CallSettingsPatch({
    this.ringSeconds,
    this.followMeTo,
    this.followMeSeconds,
    this.followMeConfirm,
    this.forwardAlwaysTo,
  });
  
  factory CallSettingsPatch.fromJson(Map<String, Object?> json) => _$CallSettingsPatchFromJson(json);
  
  final int? ringSeconds;
  final String? followMeTo;
  final int? followMeSeconds;
  final bool? followMeConfirm;
  final String? forwardAlwaysTo;

  Map<String, Object?> toJson() => _$CallSettingsPatchToJson(this);
}
