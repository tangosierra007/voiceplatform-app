// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'support.g.dart';

@JsonSerializable()
class Support {
  const Support({
    required this.name,
    this.phone,
  });
  
  factory Support.fromJson(Map<String, Object?> json) => _$SupportFromJson(json);
  
  /// The reseller's name, for example `Demo Telco`
  final String name;
  final String? phone;

  Map<String, Object?> toJson() => _$SupportToJson(this);
}
