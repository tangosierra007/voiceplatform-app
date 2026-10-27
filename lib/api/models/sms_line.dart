// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'sms_line.g.dart';

@JsonSerializable()
class SmsLine {
  const SmsLine({
    required this.id,
    required this.label,
    required this.number,
    required this.canSend,
  });
  
  factory SmsLine.fromJson(Map<String, Object?> json) => _$SmsLineFromJson(json);
  
  final String id;
  final String label;
  final String number;
  final bool canSend;

  Map<String, Object?> toJson() => _$SmsLineToJson(this);
}
