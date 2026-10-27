// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'email_request_accepted.g.dart';

@JsonSerializable()
class EmailRequestAccepted {
  const EmailRequestAccepted({
    required this.requestId,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
  });
  
  factory EmailRequestAccepted.fromJson(Map<String, Object?> json) => _$EmailRequestAcceptedFromJson(json);
  
  /// Random even for an unknown email
  final String requestId;
  final int expiresInSeconds;
  final int resendAfterSeconds;

  Map<String, Object?> toJson() => _$EmailRequestAcceptedToJson(this);
}
