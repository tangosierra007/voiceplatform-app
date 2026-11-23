// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'presence_entry.dart';

part 'colleague.g.dart';

@JsonSerializable()
class Colleague {
  const Colleague({
    required this.userId,
    required this.name,
    required this.initials,
    required this.extensionValue,
    required this.presence,
    this.voicemailDial,
    this.team,
    this.role,
    this.mobile,
  });
  
  factory Colleague.fromJson(Map<String, Object?> json) => _$ColleagueFromJson(json);
  
  final String userId;
  final String name;
  final String initials;

  /// The name has been replaced because it contains a keyword. Original name: `extension`.
  @JsonKey(name: 'extension')
  final String extensionValue;

  /// What to dial to leave this colleague a message without ringing them (spec 13 Voicemail direct, A5). Present only when their mailbox takes messages; the app dials it as given and never builds the code.
  final String? voicemailDial;
  final String? team;
  final String? role;

  /// Only when the colleague shares it
  final String? mobile;
  final PresenceEntry presence;

  Map<String, Object?> toJson() => _$ColleagueToJson(this);
}
