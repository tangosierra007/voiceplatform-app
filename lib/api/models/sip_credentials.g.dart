// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sip_credentials.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SipCredentials _$SipCredentialsFromJson(Map<String, dynamic> json) =>
    SipCredentials(
      authUsername: json['authUsername'] as String,
      instanceId: json['instanceId'] as String,
      password: json['password'] as String,
      domain: json['domain'] as String,
      outboundProxy: json['outboundProxy'] as String,
      displayName: json['displayName'] as String,
      expiresSeconds: (json['expiresSeconds'] as num).toInt(),
      pushParam: json['pushParam'] as String?,
    );

Map<String, dynamic> _$SipCredentialsToJson(SipCredentials instance) =>
    <String, dynamic>{
      'authUsername': instance.authUsername,
      'instanceId': instance.instanceId,
      'password': instance.password,
      'domain': instance.domain,
      'outboundProxy': instance.outboundProxy,
      'displayName': instance.displayName,
      'expiresSeconds': instance.expiresSeconds,
      'pushParam': instance.pushParam,
    };
