// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sms_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SmsLine _$SmsLineFromJson(Map<String, dynamic> json) => SmsLine(
  id: json['id'] as String,
  label: json['label'] as String,
  number: json['number'] as String,
  canSend: json['canSend'] as bool,
);

Map<String, dynamic> _$SmsLineToJson(SmsLine instance) => <String, dynamic>{
  'id': instance.id,
  'label': instance.label,
  'number': instance.number,
  'canSend': instance.canSend,
};
