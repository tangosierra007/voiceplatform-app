// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'me.dart';

part 'session.g.dart';

@JsonSerializable()
class Session {
  const Session({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.deviceId,
    required this.me,
  });
  
  factory Session.fromJson(Map<String, Object?> json) => _$SessionFromJson(json);
  
  final String accessToken;
  final DateTime accessExpiresAt;

  /// Rotates on every refresh; 30 days from last use
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String deviceId;
  final Me me;

  Map<String, Object?> toJson() => _$SessionToJson(this);
}
