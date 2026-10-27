// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'via_desk_phone_input.g.dart';

@JsonSerializable()
class ViaDeskPhoneInput {
  const ViaDeskPhoneInput({
    required this.number,
    this.callerId,
  });
  
  factory ViaDeskPhoneInput.fromJson(Map<String, Object?> json) => _$ViaDeskPhoneInputFromJson(json);
  
  final String number;

  /// From /me/caller-ids
  final String? callerId;

  Map<String, Object?> toJson() => _$ViaDeskPhoneInputToJson(this);
}
