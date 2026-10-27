// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'recording_direction.dart';

part 'recording.g.dart';

@JsonSerializable()
class Recording {
  const Recording({
    required this.id,
    required this.at,
    required this.direction,
    required this.number,
    required this.durationSeconds,
    this.name,
  });
  
  factory Recording.fromJson(Map<String, Object?> json) => _$RecordingFromJson(json);
  
  final String id;
  final DateTime at;
  final RecordingDirection direction;
  final String number;
  final String? name;
  final int durationSeconds;

  Map<String, Object?> toJson() => _$RecordingToJson(this);
}
