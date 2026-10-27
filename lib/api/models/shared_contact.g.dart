// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shared_contact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SharedContact _$SharedContactFromJson(Map<String, dynamic> json) =>
    SharedContact(
      id: json['id'] as String,
      name: json['name'] as String,
      numbers: (json['numbers'] as List<dynamic>)
          .map((e) => Numbers.fromJson(e as Map<String, dynamic>))
          .toList(),
      company: json['company'] as String?,
    );

Map<String, dynamic> _$SharedContactToJson(SharedContact instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'company': instance.company,
      'numbers': instance.numbers,
    };
