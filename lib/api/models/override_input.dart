// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'override_input_mode.dart';

part 'override_input.g.dart';

@JsonSerializable()
class OverrideInput {
  const OverrideInput({
    required this.mode,
    this.until,
  });
  
  factory OverrideInput.fromJson(Map<String, Object?> json) => _$OverrideInputFromJson(json);
  
  final OverrideInputMode mode;

  /// Time-boxed overrides expire by themselves (spec 11)
  final DateTime? until;

  Map<String, Object?> toJson() => _$OverrideInputToJson(this);
}
