// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post_voicemail_greetings_kind_media_url_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PostVoicemailGreetingsKindMediaUrlResponse
_$PostVoicemailGreetingsKindMediaUrlResponseFromJson(
  Map<String, dynamic> json,
) => PostVoicemailGreetingsKindMediaUrlResponse(
  url: json['url'] as String,
  expiresAt: DateTime.parse(json['expiresAt'] as String),
);

Map<String, dynamic> _$PostVoicemailGreetingsKindMediaUrlResponseToJson(
  PostVoicemailGreetingsKindMediaUrlResponse instance,
) => <String, dynamic>{
  'url': instance.url,
  'expiresAt': instance.expiresAt.toIso8601String(),
};
