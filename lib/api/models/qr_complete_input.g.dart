// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'qr_complete_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

QrCompleteInput _$QrCompleteInputFromJson(Map<String, dynamic> json) =>
    QrCompleteInput(
      qrToken: json['qrToken'] as String,
      devicePublicKey: json['devicePublicKey'] as String,
      device: DeviceInfo.fromJson(json['device'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$QrCompleteInputToJson(QrCompleteInput instance) =>
    <String, dynamic>{
      'qrToken': instance.qrToken,
      'devicePublicKey': instance.devicePublicKey,
      'device': instance.device.toJson(),
    };
