// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_request_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmailRequestInput _$EmailRequestInputFromJson(Map<String, dynamic> json) =>
    EmailRequestInput(
      email: json['email'] as String,
      requestSecret: json['requestSecret'] as String,
      device: DeviceInfo.fromJson(json['device'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$EmailRequestInputToJson(EmailRequestInput instance) =>
    <String, dynamic>{
      'email': instance.email,
      'requestSecret': instance.requestSecret,
      'device': instance.device,
    };
