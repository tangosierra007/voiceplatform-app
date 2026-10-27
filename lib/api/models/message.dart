// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'message_direction.dart';
import 'message_kind.dart';
import 'message_status.dart';

part 'message.g.dart';

@JsonSerializable()
class Message {
  const Message({
    required this.id,
    required this.threadId,
    required this.direction,
    required this.at,
    required this.kind,
    required this.status,
    this.text,
    this.senderName,
  });
  
  factory Message.fromJson(Map<String, Object?> json) => _$MessageFromJson(json);
  
  final String id;
  final String threadId;
  final MessageDirection direction;
  final DateTime at;
  final MessageKind kind;
  final String? text;

  /// Who in the tenant sent it, for `Ava · 2:16 pm · Delivered`
  final String? senderName;
  final MessageStatus status;

  Map<String, Object?> toJson() => _$MessageToJson(this);
}
