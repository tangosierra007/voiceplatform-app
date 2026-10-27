// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'greeting_kind.dart';

part 'greeting.g.dart';

@JsonSerializable()
class Greeting {
  const Greeting({
    required this.kind,
    required this.isCustom,
    this.durationSeconds,
    this.updatedAt,
  });
  
  factory Greeting.fromJson(Map<String, Object?> json) => _$GreetingFromJson(json);
  
  final GreetingKind kind;
  final bool isCustom;
  final int? durationSeconds;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => _$GreetingToJson(this);
}
