// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CallSettings _$CallSettingsFromJson(Map<String, dynamic> json) => CallSettings(
  ringDevices: (json['ringDevices'] as List<dynamic>)
      .map((e) => CallSettingsRingDevices.fromJson(e as String))
      .toList(),
  ringSeconds: (json['ringSeconds'] as num).toInt(),
  thenTo: CallSettingsThenTo.fromJson(json['thenTo'] as String),
  followMeTo: json['followMeTo'] as String?,
  followMeSeconds: (json['followMeSeconds'] as num?)?.toInt(),
  followMeConfirm: json['followMeConfirm'] as bool?,
  forwardAlwaysTo: json['forwardAlwaysTo'] as String?,
);

Map<String, dynamic> _$CallSettingsToJson(CallSettings instance) =>
    <String, dynamic>{
      'ringDevices': instance.ringDevices.map((e) => e.toJson()).toList(),
      'ringSeconds': instance.ringSeconds,
      'followMeTo': ?instance.followMeTo,
      'followMeSeconds': ?instance.followMeSeconds,
      'followMeConfirm': ?instance.followMeConfirm,
      'thenTo': instance.thenTo.toJson(),
      'forwardAlwaysTo': ?instance.forwardAlwaysTo,
    };
