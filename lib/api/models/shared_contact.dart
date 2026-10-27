// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'numbers.dart';

part 'shared_contact.g.dart';

@JsonSerializable()
class SharedContact {
  const SharedContact({
    required this.id,
    required this.name,
    required this.numbers,
    this.company,
  });
  
  factory SharedContact.fromJson(Map<String, Object?> json) => _$SharedContactFromJson(json);
  
  final String id;
  final String name;
  final String? company;
  final List<Numbers> numbers;

  Map<String, Object?> toJson() => _$SharedContactToJson(this);
}
