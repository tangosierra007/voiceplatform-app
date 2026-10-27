// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'refresh_input.g.dart';

@JsonSerializable()
class RefreshInput {
  const RefreshInput({
    required this.deviceId,
    required this.refreshToken,
    required this.timestamp,
    required this.signature,
  });
  
  factory RefreshInput.fromJson(Map<String, Object?> json) => _$RefreshInputFromJson(json);
  
  final String deviceId;
  final String refreshToken;

  /// Within 2 minutes of server time
  final DateTime timestamp;

  /// ECDSA P-256 SHA-256 over `deviceId.refreshToken.timestamp`, base64url
  final String signature;

  Map<String, Object?> toJson() => _$RefreshInputToJson(this);
}
