// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'badges.dart';
import 'me_licence.dart';
import 'permissions.dart';
import 'status.dart';
import 'support.dart';

part 'me.g.dart';

@JsonSerializable()
class Me {
  const Me({
    required this.userId,
    required this.name,
    required this.extensionValue,
    required this.tenantName,
    required this.licence,
    required this.status,
    required this.permissions,
    required this.support,
    this.initials,
    this.email,
    this.extensionName,
    this.badges,
    this.brandingKey,
  });
  
  factory Me.fromJson(Map<String, Object?> json) => _$MeFromJson(json);
  
  final String userId;
  final String name;
  final String? initials;
  final String? email;

  /// The name has been replaced because it contains a keyword. Original name: `extension`.
  @JsonKey(name: 'extension')
  final String extensionValue;
  final String? extensionName;
  final String tenantName;
  final MeLicence licence;
  final Status status;
  final Permissions permissions;
  final Badges? badges;
  final Support support;

  /// Reserved for per-reseller branding later; ignored in Stage A
  final String? brandingKey;

  Map<String, Object?> toJson() => _$MeToJson(this);
}
