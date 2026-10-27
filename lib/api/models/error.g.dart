// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Error _$ErrorFromJson(Map<String, dynamic> json) =>
    Error(error: json['error'] as String, message: json['message'] as String);

Map<String, dynamic> _$ErrorToJson(Error instance) => <String, dynamic>{
  'error': instance.error,
  'message': instance.message,
};
