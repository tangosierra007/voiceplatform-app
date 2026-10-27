// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'override_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OverrideInput _$OverrideInputFromJson(Map<String, dynamic> json) =>
    OverrideInput(
      mode: OverrideInputMode.fromJson(json['mode'] as String),
      until: json['until'] == null
          ? null
          : DateTime.parse(json['until'] as String),
    );

Map<String, dynamic> _$OverrideInputToJson(OverrideInput instance) =>
    <String, dynamic>{
      'mode': instance.mode,
      'until': instance.until?.toIso8601String(),
    };
