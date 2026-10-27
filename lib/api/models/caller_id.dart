// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'caller_id.g.dart';

@JsonSerializable()
class CallerId {
  const CallerId({
    required this.value,
    required this.label,
    required this.isDefault,
  });
  
  factory CallerId.fromJson(Map<String, Object?> json) => _$CallerIdFromJson(json);
  
  /// E.164, or `withheld`
  final String value;
  final String label;
  final bool isDefault;

  Map<String, Object?> toJson() => _$CallerIdToJson(this);
}
