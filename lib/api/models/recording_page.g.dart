// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecordingPage _$RecordingPageFromJson(Map<String, dynamic> json) =>
    RecordingPage(
      items: (json['items'] as List<dynamic>)
          .map((e) => Recording.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextBefore: json['nextBefore'] as String?,
    );

Map<String, dynamic> _$RecordingPageToJson(RecordingPage instance) =>
    <String, dynamic>{
      'items': instance.items.map((e) => e.toJson()).toList(),
      'nextBefore': ?instance.nextBefore,
    };
