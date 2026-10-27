// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'send_input.g.dart';

@JsonSerializable()
class SendInput {
  const SendInput({
    required this.lineId,
    required this.to,
    required this.text,
  });
  
  factory SendInput.fromJson(Map<String, Object?> json) => _$SendInputFromJson(json);
  
  final String lineId;
  final String to;
  final String text;

  Map<String, Object?> toJson() => _$SendInputToJson(this);
}
