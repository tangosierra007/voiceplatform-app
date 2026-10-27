// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'device_info.dart';

part 'qr_complete_input.g.dart';

@JsonSerializable()
class QrCompleteInput {
  const QrCompleteInput({
    required this.qrToken,
    required this.devicePublicKey,
    required this.device,
  });
  
  factory QrCompleteInput.fromJson(Map<String, Object?> json) => _$QrCompleteInputFromJson(json);
  
  final String qrToken;
  final String devicePublicKey;
  final DeviceInfo device;

  Map<String, Object?> toJson() => _$QrCompleteInputToJson(this);
}
