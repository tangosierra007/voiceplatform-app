// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'status_input_status.dart';

part 'status_input.g.dart';

@JsonSerializable()
class StatusInput {
  const StatusInput({
    required this.status,
    this.dndUntil,
  });
  
  factory StatusInput.fromJson(Map<String, Object?> json) => _$StatusInputFromJson(json);
  
  final StatusInputStatus status;

  /// Only with `dnd`; cleared by itself at that time (A4)
  final DateTime? dndUntil;

  Map<String, Object?> toJson() => _$StatusInputToJson(this);
}
