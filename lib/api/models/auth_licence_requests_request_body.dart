// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'auth_licence_requests_request_body.g.dart';

@JsonSerializable()
class AuthLicenceRequestsRequestBody {
  const AuthLicenceRequestsRequestBody({
    required this.refusalToken,
  });
  
  factory AuthLicenceRequestsRequestBody.fromJson(Map<String, Object?> json) => _$AuthLicenceRequestsRequestBodyFromJson(json);
  
  final String refusalToken;

  Map<String, Object?> toJson() => _$AuthLicenceRequestsRequestBodyToJson(this);
}
