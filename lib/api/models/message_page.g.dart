// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessagePage _$MessagePageFromJson(Map<String, dynamic> json) => MessagePage(
  items: (json['items'] as List<dynamic>)
      .map((e) => Message.fromJson(e as Map<String, dynamic>))
      .toList(),
  nextBefore: json['nextBefore'] as String?,
);

Map<String, dynamic> _$MessagePageToJson(MessagePage instance) =>
    <String, dynamic>{
      'items': instance.items,
      'nextBefore': instance.nextBefore,
    };
