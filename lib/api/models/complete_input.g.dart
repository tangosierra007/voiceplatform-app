// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'complete_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CompleteInput _$CompleteInputFromJson(Map<String, dynamic> json) =>
    CompleteInput(
      requestSecret: json['requestSecret'] as String,
      devicePublicKey: json['devicePublicKey'] as String,
      device: DeviceInfo.fromJson(json['device'] as Map<String, dynamic>),
      code: json['code'] as String?,
      linkToken: json['linkToken'] as String?,
    );

Map<String, dynamic> _$CompleteInputToJson(CompleteInput instance) =>
    <String, dynamic>{
      'requestSecret': instance.requestSecret,
      'code': ?instance.code,
      'linkToken': ?instance.linkToken,
      'devicePublicKey': instance.devicePublicKey,
      'device': instance.device.toJson(),
    };
