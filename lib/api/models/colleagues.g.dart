// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'colleagues.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Colleagues _$ColleaguesFromJson(Map<String, dynamic> json) => Colleagues(
  total: (json['total'] as num).toInt(),
  freeNow: (json['freeNow'] as num).toInt(),
  items: (json['items'] as List<dynamic>)
      .map((e) => Colleague.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ColleaguesToJson(Colleagues instance) =>
    <String, dynamic>{
      'total': instance.total,
      'freeNow': instance.freeNow,
      'items': instance.items,
    };
