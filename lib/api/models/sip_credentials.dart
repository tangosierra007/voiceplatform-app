// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'sip_credentials.g.dart';

/// Maps one to one onto `SipAccount` in `call_engine.dart`
@JsonSerializable()
class SipCredentials {
  const SipCredentials({
    required this.authUsername,
    required this.password,
    required this.domain,
    required this.outboundProxy,
    required this.displayName,
    required this.expiresSeconds,
    this.pushParam,
  });
  
  factory SipCredentials.fromJson(Map<String, Object?> json) => _$SipCredentialsFromJson(json);
  
  final String authUsername;
  final String password;
  final String domain;
  final String outboundProxy;
  final String displayName;
  final int expiresSeconds;
  final String? pushParam;

  Map<String, Object?> toJson() => _$SipCredentialsToJson(this);
}
