// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'device_summary_kind.dart';

part 'device_summary.g.dart';

@JsonSerializable()
class DeviceSummary {
  const DeviceSummary({
    required this.id,
    required this.kind,
    required this.label,
    required this.isThisDevice,
    required this.rings,
    required this.canSignOut,
    this.lastSeenAt,
    this.signedInAt,
  });
  
  factory DeviceSummary.fromJson(Map<String, Object?> json) => _$DeviceSummaryFromJson(json);
  
  final String id;
  final DeviceSummaryKind kind;
  final String label;
  final bool isThisDevice;
  final bool rings;

  /// False for desk phones (managed by the admin)
  final bool canSignOut;
  final DateTime? lastSeenAt;
  final DateTime? signedInAt;

  Map<String, Object?> toJson() => _$DeviceSummaryToJson(this);
}
