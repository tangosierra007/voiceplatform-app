// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'device_info.dart';

part 'complete_input.g.dart';

@JsonSerializable()
class CompleteInput {
  const CompleteInput({
    required this.requestSecret,
    required this.devicePublicKey,
    required this.device,
    this.code,
    this.linkToken,
  });
  
  factory CompleteInput.fromJson(Map<String, Object?> json) => _$CompleteInputFromJson(json);
  
  final String requestSecret;
  final String? code;

  /// From the App Link `https://<portal host>/app/signin/<requestId>/<linkToken>`
  final String? linkToken;

  /// SPKI DER, base64url, P-256 from Android Keystore (Secure Enclave on iOS)
  final String devicePublicKey;
  final DeviceInfo device;

  Map<String, Object?> toJson() => _$CompleteInputToJson(this);
}
