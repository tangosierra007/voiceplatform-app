// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'signed_out_error.dart';
import 'support.dart';

part 'signed_out.g.dart';

@JsonSerializable()
class SignedOut {
  const SignedOut({
    required this.error,
    required this.message,
    this.revokedBy,
    this.revokedAt,
    this.extensionValue,
    this.support,
  });
  
  factory SignedOut.fromJson(Map<String, Object?> json) => _$SignedOutFromJson(json);
  
  final SignedOutError error;
  final String message;

  /// Name and role as the screen shows, for example `Priya Shah, your admin`
  final String? revokedBy;
  final DateTime? revokedAt;

  /// The name has been replaced because it contains a keyword. Original name: `extension`.
  @JsonKey(name: 'extension')
  final String? extensionValue;
  final Support? support;

  Map<String, Object?> toJson() => _$SignedOutToJson(this);
}
