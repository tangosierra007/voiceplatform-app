// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'voicemail_pin_request_body.g.dart';

@JsonSerializable()
class VoicemailPinRequestBody {
  const VoicemailPinRequestBody({
    required this.pin,
  });
  
  factory VoicemailPinRequestBody.fromJson(Map<String, Object?> json) => _$VoicemailPinRequestBodyFromJson(json);
  
  final String pin;

  Map<String, Object?> toJson() => _$VoicemailPinRequestBodyToJson(this);
}
