// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post_recordings_id_media_url_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PostRecordingsIdMediaUrlResponse _$PostRecordingsIdMediaUrlResponseFromJson(
  Map<String, dynamic> json,
) => PostRecordingsIdMediaUrlResponse(
  url: json['url'] as String,
  expiresAt: DateTime.parse(json['expiresAt'] as String),
);

Map<String, dynamic> _$PostRecordingsIdMediaUrlResponseToJson(
  PostRecordingsIdMediaUrlResponse instance,
) => <String, dynamic>{
  'url': instance.url,
  'expiresAt': instance.expiresAt.toIso8601String(),
};
