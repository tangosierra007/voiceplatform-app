// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'send_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SendInput _$SendInputFromJson(Map<String, dynamic> json) => SendInput(
  lineId: json['lineId'] as String,
  to: json['to'] as String,
  text: json['text'] as String,
);

Map<String, dynamic> _$SendInputToJson(SendInput instance) => <String, dynamic>{
  'lineId': instance.lineId,
  'to': instance.to,
  'text': instance.text,
};
