// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'presence.dart';

part 'presence_entry.g.dart';

@JsonSerializable()
class PresenceEntry {
  const PresenceEntry({
    required this.extensionValue,
    required this.presence,
    this.since,
    this.dndUntil,
    this.detail,
  });
  
  factory PresenceEntry.fromJson(Map<String, Object?> json) => _$PresenceEntryFromJson(json);
  
  /// The name has been replaced because it contains a keyword. Original name: `extension`.
  @JsonKey(name: 'extension')
  final String extensionValue;
  final Presence presence;

  /// For the call timer, `On a call · 1:37`
  final DateTime? since;
  final DateTime? dndUntil;

  /// Text the user set, for desktop
  final String? detail;

  Map<String, Object?> toJson() => _$PresenceEntryToJson(this);
}
