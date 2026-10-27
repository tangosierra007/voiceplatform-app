// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'auth_email_requests_request_id_resend_request_body.g.dart';

@JsonSerializable()
class AuthEmailRequestsRequestIdResendRequestBody {
  const AuthEmailRequestsRequestIdResendRequestBody({
    required this.requestSecret,
  });
  
  factory AuthEmailRequestsRequestIdResendRequestBody.fromJson(Map<String, Object?> json) => _$AuthEmailRequestsRequestIdResendRequestBodyFromJson(json);
  
  final String requestSecret;

  Map<String, Object?> toJson() => _$AuthEmailRequestsRequestIdResendRequestBodyToJson(this);
}
