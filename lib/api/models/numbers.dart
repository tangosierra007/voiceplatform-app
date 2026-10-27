// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'numbers.g.dart';

@JsonSerializable()
class Numbers {
  const Numbers({
    required this.label,
    required this.number,
  });
  
  factory Numbers.fromJson(Map<String, Object?> json) => _$NumbersFromJson(json);
  
  final String label;
  final String number;

  Map<String, Object?> toJson() => _$NumbersToJson(this);
}
