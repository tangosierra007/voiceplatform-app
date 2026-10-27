// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voicemail_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VoicemailPage _$VoicemailPageFromJson(Map<String, dynamic> json) =>
    VoicemailPage(
      items: (json['items'] as List<dynamic>)
          .map((e) => VoicemailMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextBefore: json['nextBefore'] as String?,
    );

Map<String, dynamic> _$VoicemailPageToJson(VoicemailPage instance) =>
    <String, dynamic>{
      'items': instance.items.map((e) => e.toJson()).toList(),
      'nextBefore': ?instance.nextBefore,
    };
