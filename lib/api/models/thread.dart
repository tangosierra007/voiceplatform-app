// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'thread_channel.dart';

part 'thread.g.dart';

@JsonSerializable()
class Thread {
  const Thread({
    required this.id,
    required this.lineId,
    required this.lineLabel,
    required this.number,
    required this.lastAt,
    required this.lastText,
    required this.unread,
    this.name,
    this.channel,
  });
  
  factory Thread.fromJson(Map<String, Object?> json) => _$ThreadFromJson(json);
  
  final String id;
  final String lineId;
  final String lineLabel;
  final String number;
  final String? name;
  final DateTime lastAt;

  /// Prefixed `You: ` when mine; `Sent a picture message (not shown yet)` for MMS
  final String lastText;
  final int unread;

  /// Generic conversations model; whatsapp later
  final ThreadChannel? channel;

  Map<String, Object?> toJson() => _$ThreadToJson(this);
}
