// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'history_entry_direction.dart';
import 'history_entry_outcome.dart';

part 'history_entry.g.dart';

@JsonSerializable()
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.at,
    required this.direction,
    required this.outcome,
    required this.number,
    this.name,
    this.durationSeconds,
    this.answeredBy,
    this.line,
    this.mine,
    this.voicemailId,
  });
  
  factory HistoryEntry.fromJson(Map<String, Object?> json) => _$HistoryEntryFromJson(json);
  
  final String id;
  final DateTime at;
  final HistoryEntryDirection direction;
  final HistoryEntryOutcome outcome;

  /// E.164, or `anonymous` (shown as Private)
  final String number;

  /// Colleague or shared contact; the app may overlay a phone contact locally
  final String? name;
  final int? durationSeconds;

  /// `Mia on her desk phone`
  final String? answeredBy;

  /// Number or group called, for example `Sales`
  final String? line;
  final bool? mine;
  final String? voicemailId;

  Map<String, Object?> toJson() => _$HistoryEntryToJson(this);
}
