// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post_voicemail_messages_id_media_url_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PostVoicemailMessagesIdMediaUrlResponse
_$PostVoicemailMessagesIdMediaUrlResponseFromJson(Map<String, dynamic> json) =>
    PostVoicemailMessagesIdMediaUrlResponse(
      url: json['url'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );

Map<String, dynamic> _$PostVoicemailMessagesIdMediaUrlResponseToJson(
  PostVoicemailMessagesIdMediaUrlResponse instance,
) => <String, dynamic>{
  'url': instance.url,
  'expiresAt': instance.expiresAt.toIso8601String(),
};
