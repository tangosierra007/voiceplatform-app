// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'refresh_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RefreshInput _$RefreshInputFromJson(Map<String, dynamic> json) => RefreshInput(
  deviceId: json['deviceId'] as String,
  refreshToken: json['refreshToken'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  signature: json['signature'] as String,
);

Map<String, dynamic> _$RefreshInputToJson(RefreshInput instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'refreshToken': instance.refreshToken,
      'timestamp': instance.timestamp.toIso8601String(),
      'signature': instance.signature,
    };
