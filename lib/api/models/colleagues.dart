// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'colleague.dart';
import 'desk.dart';

part 'colleagues.g.dart';

@JsonSerializable()
class Colleagues {
  const Colleagues({
    required this.total,
    required this.freeNow,
    required this.items,
    this.desks,
    this.desksFree,
  });
  
  factory Colleagues.fromJson(Map<String, Object?> json) => _$ColleaguesFromJson(json);
  
  final int total;
  final int freeNow;
  final List<Colleague> items;

  /// Additive (spec 31, G14): active extensions with no active user (a front desk, a shared phone, a person invited but not signed in yet), by display name, never one an admin switched out of the apps. Sent while the platform lists desks (on by default, decision 257); a reply without it is still valid. items, total and freeNow stay people only.
  final List<Desk>? desks;
  final int? desksFree;

  Map<String, Object?> toJson() => _$ColleaguesToJson(this);
}
