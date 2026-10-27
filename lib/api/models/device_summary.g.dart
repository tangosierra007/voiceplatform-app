// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceSummary _$DeviceSummaryFromJson(Map<String, dynamic> json) =>
    DeviceSummary(
      id: json['id'] as String,
      kind: DeviceSummaryKind.fromJson(json['kind'] as String),
      label: json['label'] as String,
      isThisDevice: json['isThisDevice'] as bool,
      rings: json['rings'] as bool,
      canSignOut: json['canSignOut'] as bool,
      lastSeenAt: json['lastSeenAt'] == null
          ? null
          : DateTime.parse(json['lastSeenAt'] as String),
      signedInAt: json['signedInAt'] == null
          ? null
          : DateTime.parse(json['signedInAt'] as String),
    );

Map<String, dynamic> _$DeviceSummaryToJson(DeviceSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'kind': instance.kind.toJson(),
      'label': instance.label,
      'isThisDevice': instance.isThisDevice,
      'rings': instance.rings,
      'canSignOut': instance.canSignOut,
      'lastSeenAt': ?instance.lastSeenAt?.toIso8601String(),
      'signedInAt': ?instance.signedInAt?.toIso8601String(),
    };
