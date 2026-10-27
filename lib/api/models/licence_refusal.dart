// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'licence_refusal_error.dart';

part 'licence_refusal.g.dart';

@JsonSerializable()
class LicenceRefusal {
  const LicenceRefusal({
    required this.error,
    required this.message,
    this.extensionValue,
    this.extensionName,
    this.refusalToken,
  });
  
  factory LicenceRefusal.fromJson(Map<String, Object?> json) => _$LicenceRefusalFromJson(json);
  
  final LicenceRefusalError error;
  final String message;

  /// The name has been replaced because it contains a keyword. Original name: `extension`.
  @JsonKey(name: 'extension')
  final String? extensionValue;
  final String? extensionName;

  /// For POST /auth/licence-requests; 1 hour
  final String? refusalToken;

  Map<String, Object?> toJson() => _$LicenceRefusalToJson(this);
}
