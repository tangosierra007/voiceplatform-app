// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'colleague.dart';

part 'colleagues.g.dart';

@JsonSerializable()
class Colleagues {
  const Colleagues({
    required this.total,
    required this.freeNow,
    required this.items,
  });
  
  factory Colleagues.fromJson(Map<String, Object?> json) => _$ColleaguesFromJson(json);
  
  final int total;
  final int freeNow;
  final List<Colleague> items;

  Map<String, Object?> toJson() => _$ColleaguesToJson(this);
}
