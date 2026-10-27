// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'team_ring_order.dart';

part 'team.g.dart';

@JsonSerializable()
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.freeCount,
    required this.members,
    this.number,
    this.ringOrder,
  });
  
  factory Team.fromJson(Map<String, Object?> json) => _$TeamFromJson(json);
  
  final String id;
  final String name;

  /// Extension or DID that rings the team
  final String? number;
  final int memberCount;
  final int freeCount;
  final TeamRingOrder? ringOrder;
  final List<String> members;

  Map<String, Object?> toJson() => _$TeamToJson(this);
}
