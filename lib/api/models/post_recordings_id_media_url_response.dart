// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'post_recordings_id_media_url_response.g.dart';

@JsonSerializable()
class PostRecordingsIdMediaUrlResponse {
  const PostRecordingsIdMediaUrlResponse({
    required this.url,
    required this.expiresAt,
  });
  
  factory PostRecordingsIdMediaUrlResponse.fromJson(Map<String, Object?> json) => _$PostRecordingsIdMediaUrlResponseFromJson(json);
  
  /// `/app/v1/media/<token>`, 5 minutes
  final String url;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => _$PostRecordingsIdMediaUrlResponseToJson(this);
}
