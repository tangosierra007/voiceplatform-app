// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voicemail_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VoicemailMessage _$VoicemailMessageFromJson(Map<String, dynamic> json) =>
    VoicemailMessage(
      id: json['id'] as String,
      boxId: json['boxId'] as String,
      boxName: json['boxName'] as String,
      at: DateTime.parse(json['at'] as String),
      number: json['number'] as String,
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      heard: json['heard'] as bool,
      name: json['name'] as String?,
      waveform: (json['waveform'] as List<dynamic>?)
          ?.map((e) => e as num)
          .toList(),
      transcript: json['transcript'],
    );

Map<String, dynamic> _$VoicemailMessageToJson(VoicemailMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'boxId': instance.boxId,
      'boxName': instance.boxName,
      'at': instance.at.toIso8601String(),
      'number': instance.number,
      'name': instance.name,
      'durationSeconds': instance.durationSeconds,
      'heard': instance.heard,
      'waveform': instance.waveform,
      'transcript': instance.transcript,
    };
