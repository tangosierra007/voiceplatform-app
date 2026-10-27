// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'history_seen_request_body.g.dart';

@JsonSerializable()
class HistorySeenRequestBody {
  const HistorySeenRequestBody({
    required this.upTo,
  });
  
  factory HistorySeenRequestBody.fromJson(Map<String, Object?> json) => _$HistorySeenRequestBodyFromJson(json);
  
  final DateTime upTo;

  Map<String, Object?> toJson() => _$HistorySeenRequestBodyToJson(this);
}
