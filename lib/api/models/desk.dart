// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'presence_entry.dart';

part 'desk.g.dart';

@JsonSerializable()
class Desk {
  const Desk({
    required this.extensionId,
    required this.extensionValue,
    required this.name,
    required this.initials,
    required this.presence,
    this.team,
  });
  
  factory Desk.fromJson(Map<String, Object?> json) => _$DeskFromJson(json);
  
  final String extensionId;

  /// The name has been replaced because it contains a keyword. Original name: `extension`.
  @JsonKey(name: 'extension')
  final String extensionValue;
  final String name;
  final String initials;
  final String? team;
  final PresenceEntry presence;

  Map<String, Object?> toJson() => _$DeskToJson(this);
}
