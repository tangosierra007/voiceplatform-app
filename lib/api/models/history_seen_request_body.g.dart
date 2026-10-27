// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_seen_request_body.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HistorySeenRequestBody _$HistorySeenRequestBodyFromJson(
  Map<String, dynamic> json,
) => HistorySeenRequestBody(upTo: DateTime.parse(json['upTo'] as String));

Map<String, dynamic> _$HistorySeenRequestBodyToJson(
  HistorySeenRequestBody instance,
) => <String, dynamic>{'upTo': instance.upTo.toIso8601String()};
