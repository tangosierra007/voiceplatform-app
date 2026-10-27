// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_request_accepted.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmailRequestAccepted _$EmailRequestAcceptedFromJson(
  Map<String, dynamic> json,
) => EmailRequestAccepted(
  requestId: json['requestId'] as String,
  expiresInSeconds: (json['expiresInSeconds'] as num).toInt(),
  resendAfterSeconds: (json['resendAfterSeconds'] as num).toInt(),
);

Map<String, dynamic> _$EmailRequestAcceptedToJson(
  EmailRequestAccepted instance,
) => <String, dynamic>{
  'requestId': instance.requestId,
  'expiresInSeconds': instance.expiresInSeconds,
  'resendAfterSeconds': instance.resendAfterSeconds,
};
