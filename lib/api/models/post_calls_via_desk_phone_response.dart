// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'post_calls_via_desk_phone_response.g.dart';

@JsonSerializable()
class PostCallsViaDeskPhoneResponse {
  const PostCallsViaDeskPhoneResponse({
    required this.deskPhone,
  });
  
  factory PostCallsViaDeskPhoneResponse.fromJson(Map<String, Object?> json) => _$PostCallsViaDeskPhoneResponseFromJson(json);
  
  /// For example `Desk phone 202`
  final String deskPhone;

  Map<String, Object?> toJson() => _$PostCallsViaDeskPhoneResponseToJson(this);
}
