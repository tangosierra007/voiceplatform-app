// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'recording.dart';

part 'recording_page.g.dart';

@JsonSerializable()
class RecordingPage {
  const RecordingPage({
    required this.items,
    this.nextBefore,
  });
  
  factory RecordingPage.fromJson(Map<String, Object?> json) => _$RecordingPageFromJson(json);
  
  final List<Recording> items;
  final String? nextBefore;

  Map<String, Object?> toJson() => _$RecordingPageToJson(this);
}
