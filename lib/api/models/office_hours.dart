// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'office_hours_mode.dart';

part 'office_hours.g.dart';

@JsonSerializable()
class OfficeHours {
  const OfficeHours({
    required this.id,
    required this.name,
    required this.mode,
    required this.openNow,
    this.until,
    this.summary,
  });
  
  factory OfficeHours.fromJson(Map<String, Object?> json) => _$OfficeHoursFromJson(json);
  
  final String id;
  final String name;
  final OfficeHoursMode mode;
  final bool openNow;
  final DateTime? until;
  final String? summary;

  Map<String, Object?> toJson() => _$OfficeHoursToJson(this);
}
