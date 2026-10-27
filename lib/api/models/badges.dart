// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'badges.g.dart';

@JsonSerializable()
class Badges {
  const Badges({
    this.recents,
    this.messages,
  });
  
  factory Badges.fromJson(Map<String, Object?> json) => _$BadgesFromJson(json);
  
  /// New voicemail plus unseen missed calls
  final int? recents;
  final int? messages;

  Map<String, Object?> toJson() => _$BadgesToJson(this);
}
