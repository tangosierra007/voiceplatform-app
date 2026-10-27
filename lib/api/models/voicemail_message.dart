// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'voicemail_message.g.dart';

@JsonSerializable()
class VoicemailMessage {
  const VoicemailMessage({
    required this.id,
    required this.boxId,
    required this.boxName,
    required this.at,
    required this.number,
    required this.durationSeconds,
    required this.heard,
    this.name,
    this.waveform,
    this.transcript,
  });
  
  factory VoicemailMessage.fromJson(Map<String, Object?> json) => _$VoicemailMessageFromJson(json);
  
  final String id;
  final String boxId;
  final String boxName;
  final DateTime at;
  final String number;
  final String? name;
  final int durationSeconds;
  final bool heard;

  /// Peaks for the inline player
  final List<num>? waveform;

  /// Reserved; transcripts land later with self-hosted speech to text
  final dynamic transcript;

  Map<String, Object?> toJson() => _$VoicemailMessageToJson(this);
}
