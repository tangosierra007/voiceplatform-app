// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'message.dart';

part 'message_page.g.dart';

@JsonSerializable()
class MessagePage {
  const MessagePage({
    required this.items,
    this.nextBefore,
  });
  
  factory MessagePage.fromJson(Map<String, Object?> json) => _$MessagePageFromJson(json);
  
  final List<Message> items;
  final String? nextBefore;

  Map<String, Object?> toJson() => _$MessagePageToJson(this);
}
