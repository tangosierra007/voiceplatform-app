// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'status_status.dart';

part 'status.g.dart';

@JsonSerializable()
class Status {
  const Status({
    required this.status,
    this.dndUntil,
    this.changedAt,
  });
  
  factory Status.fromJson(Map<String, Object?> json) => _$StatusFromJson(json);
  
  final StatusStatus status;
  final DateTime? dndUntil;
  final DateTime? changedAt;

  Map<String, Object?> toJson() => _$StatusToJson(this);
}
