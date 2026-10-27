// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HistoryPage _$HistoryPageFromJson(Map<String, dynamic> json) => HistoryPage(
  items: (json['items'] as List<dynamic>)
      .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
      .toList(),
  counts: Counts.fromJson(json['counts'] as Map<String, dynamic>),
  nextBefore: json['nextBefore'] as String?,
);

Map<String, dynamic> _$HistoryPageToJson(HistoryPage instance) =>
    <String, dynamic>{
      'items': instance.items,
      'nextBefore': instance.nextBefore,
      'counts': instance.counts,
    };
