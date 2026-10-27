// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'voicemail_box_kind.dart';

part 'voicemail_box.g.dart';

@JsonSerializable()
class VoicemailBox {
  const VoicemailBox({
    required this.id,
    required this.name,
    required this.kind,
    required this.newCount,
    required this.totalCount,
  });
  
  factory VoicemailBox.fromJson(Map<String, Object?> json) => _$VoicemailBoxFromJson(json);
  
  final String id;
  final String name;
  final VoicemailBoxKind kind;
  final int newCount;
  final int totalCount;

  Map<String, Object?> toJson() => _$VoicemailBoxToJson(this);
}
