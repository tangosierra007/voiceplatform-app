// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'voicemail_messages_id_read_request_body.g.dart';

@JsonSerializable()
class VoicemailMessagesIdReadRequestBody {
  const VoicemailMessagesIdReadRequestBody({
    required this.heard,
  });
  
  factory VoicemailMessagesIdReadRequestBody.fromJson(Map<String, Object?> json) => _$VoicemailMessagesIdReadRequestBodyFromJson(json);
  
  final bool heard;

  Map<String, Object?> toJson() => _$VoicemailMessagesIdReadRequestBodyToJson(this);
}
