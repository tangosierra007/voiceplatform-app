// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'badges.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Badges _$BadgesFromJson(Map<String, dynamic> json) => Badges(
  recents: (json['recents'] as num?)?.toInt(),
  messages: (json['messages'] as num?)?.toInt(),
);

Map<String, dynamic> _$BadgesToJson(Badges instance) => <String, dynamic>{
  'recents': instance.recents,
  'messages': instance.messages,
};
