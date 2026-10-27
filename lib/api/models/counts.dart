// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'counts.g.dart';

@JsonSerializable()
class Counts {
  const Counts({
    required this.missed,
    required this.voicemail,
  });
  
  factory Counts.fromJson(Map<String, Object?> json) => _$CountsFromJson(json);
  
  final int missed;
  final int voicemail;

  Map<String, Object?> toJson() => _$CountsToJson(this);
}
