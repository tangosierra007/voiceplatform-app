// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HistoryEntry _$HistoryEntryFromJson(Map<String, dynamic> json) => HistoryEntry(
  id: json['id'] as String,
  at: DateTime.parse(json['at'] as String),
  direction: HistoryEntryDirection.fromJson(json['direction'] as String),
  outcome: HistoryEntryOutcome.fromJson(json['outcome'] as String),
  number: json['number'] as String,
  name: json['name'] as String?,
  durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
  answeredBy: json['answeredBy'] as String?,
  line: json['line'] as String?,
  mine: json['mine'] as bool?,
  voicemailId: json['voicemailId'] as String?,
);

Map<String, dynamic> _$HistoryEntryToJson(HistoryEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'at': instance.at.toIso8601String(),
      'direction': instance.direction.toJson(),
      'outcome': instance.outcome.toJson(),
      'number': instance.number,
      'name': ?instance.name,
      'durationSeconds': ?instance.durationSeconds,
      'answeredBy': ?instance.answeredBy,
      'line': ?instance.line,
      'mine': ?instance.mine,
      'voicemailId': ?instance.voicemailId,
    };
