// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'tokens.g.dart';

@JsonSerializable()
class Tokens {
  const Tokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });
  
  factory Tokens.fromJson(Map<String, Object?> json) => _$TokensFromJson(json);
  
  final String accessToken;
  final DateTime accessExpiresAt;

  /// Rotates on every refresh; 30 days from last use
  final String refreshToken;
  final DateTime refreshExpiresAt;

  Map<String, Object?> toJson() => _$TokensToJson(this);
}
