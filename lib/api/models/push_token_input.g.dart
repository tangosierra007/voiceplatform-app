// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_token_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PushTokenInput _$PushTokenInputFromJson(Map<String, dynamic> json) =>
    PushTokenInput(
      provider: PushTokenInputProvider.fromJson(json['provider'] as String),
      token: json['token'] as String,
    );

Map<String, dynamic> _$PushTokenInputToJson(PushTokenInput instance) =>
    <String, dynamic>{
      'provider': instance.provider.toJson(),
      'token': instance.token,
    };
