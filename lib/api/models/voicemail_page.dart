// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'voicemail_message.dart';

part 'voicemail_page.g.dart';

@JsonSerializable()
class VoicemailPage {
  const VoicemailPage({
    required this.items,
    this.nextBefore,
  });
  
  factory VoicemailPage.fromJson(Map<String, Object?> json) => _$VoicemailPageFromJson(json);
  
  final List<VoicemailMessage> items;
  final String? nextBefore;

  Map<String, Object?> toJson() => _$VoicemailPageToJson(this);
}
