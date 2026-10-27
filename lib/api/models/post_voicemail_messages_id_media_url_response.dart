// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'post_voicemail_messages_id_media_url_response.g.dart';

@JsonSerializable()
class PostVoicemailMessagesIdMediaUrlResponse {
  const PostVoicemailMessagesIdMediaUrlResponse({
    required this.url,
    required this.expiresAt,
  });
  
  factory PostVoicemailMessagesIdMediaUrlResponse.fromJson(Map<String, Object?> json) => _$PostVoicemailMessagesIdMediaUrlResponseFromJson(json);
  
  /// `/app/v1/media/<token>`, 5 minutes
  final String url;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => _$PostVoicemailMessagesIdMediaUrlResponseToJson(this);
}
