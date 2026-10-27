// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'device_info.dart';

part 'email_request_input.g.dart';

@JsonSerializable()
class EmailRequestInput {
  const EmailRequestInput({
    required this.email,
    required this.requestSecret,
    required this.device,
  });
  
  factory EmailRequestInput.fromJson(Map<String, Object?> json) => _$EmailRequestInputFromJson(json);
  
  final String email;

  /// 32 random bytes, base64url; only its SHA-256 is stored
  final String requestSecret;
  final DeviceInfo device;

  Map<String, Object?> toJson() => _$EmailRequestInputToJson(this);
}
