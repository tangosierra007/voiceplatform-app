// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_settings_patch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CallSettingsPatch _$CallSettingsPatchFromJson(Map<String, dynamic> json) =>
    CallSettingsPatch(
      ringSeconds: (json['ringSeconds'] as num?)?.toInt(),
      followMeTo: json['followMeTo'] as String?,
      followMeSeconds: (json['followMeSeconds'] as num?)?.toInt(),
      followMeConfirm: json['followMeConfirm'] as bool?,
      forwardAlwaysTo: json['forwardAlwaysTo'] as String?,
    );

Map<String, dynamic> _$CallSettingsPatchToJson(CallSettingsPatch instance) =>
    <String, dynamic>{
      'ringSeconds': ?instance.ringSeconds,
      'followMeTo': ?instance.followMeTo,
      'followMeSeconds': ?instance.followMeSeconds,
      'followMeConfirm': ?instance.followMeConfirm,
      'forwardAlwaysTo': ?instance.forwardAlwaysTo,
    };
