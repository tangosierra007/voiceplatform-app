// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Me _$MeFromJson(Map<String, dynamic> json) => Me(
  userId: json['userId'] as String,
  name: json['name'] as String,
  extensionValue: json['extension'] as String,
  tenantName: json['tenantName'] as String,
  licence: MeLicence.fromJson(json['licence'] as String),
  status: Status.fromJson(json['status'] as Map<String, dynamic>),
  permissions: Permissions.fromJson(
    json['permissions'] as Map<String, dynamic>,
  ),
  support: Support.fromJson(json['support'] as Map<String, dynamic>),
  initials: json['initials'] as String?,
  email: json['email'] as String?,
  extensionName: json['extensionName'] as String?,
  badges: json['badges'] == null
      ? null
      : Badges.fromJson(json['badges'] as Map<String, dynamic>),
  brandingKey: json['brandingKey'] as String?,
);

Map<String, dynamic> _$MeToJson(Me instance) => <String, dynamic>{
  'userId': instance.userId,
  'name': instance.name,
  'initials': ?instance.initials,
  'email': ?instance.email,
  'extension': instance.extensionValue,
  'extensionName': ?instance.extensionName,
  'tenantName': instance.tenantName,
  'licence': instance.licence.toJson(),
  'status': instance.status.toJson(),
  'permissions': instance.permissions.toJson(),
  'badges': ?instance.badges?.toJson(),
  'support': instance.support.toJson(),
  'brandingKey': ?instance.brandingKey,
};
