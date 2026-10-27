// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'permissions.g.dart';

@JsonSerializable()
class Permissions {
  const Permissions({
    required this.recordings,
    required this.officeHours,
    required this.messages,
    required this.sharedVoicemail,
  });
  
  factory Permissions.fromJson(Map<String, Object?> json) => _$PermissionsFromJson(json);
  
  final bool recordings;

  /// At least one time condition grants this user the override (APP11)
  final bool officeHours;

  /// At least one SMS line
  final bool messages;
  final bool sharedVoicemail;

  Map<String, Object?> toJson() => _$PermissionsToJson(this);
}
