// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThreadPage _$ThreadPageFromJson(Map<String, dynamic> json) => ThreadPage(
  items: (json['items'] as List<dynamic>)
      .map((e) => Thread.fromJson(e as Map<String, dynamic>))
      .toList(),
  unreadTotal: (json['unreadTotal'] as num).toInt(),
  nextBefore: json['nextBefore'] as String?,
);

Map<String, dynamic> _$ThreadPageToJson(ThreadPage instance) =>
    <String, dynamic>{
      'items': instance.items.map((e) => e.toJson()).toList(),
      'nextBefore': ?instance.nextBefore,
      'unreadTotal': instance.unreadTotal,
    };
