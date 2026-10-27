// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'push_token_input_provider.dart';

part 'push_token_input.g.dart';

@JsonSerializable()
class PushTokenInput {
  const PushTokenInput({
    required this.provider,
    required this.token,
  });
  
  factory PushTokenInput.fromJson(Map<String, Object?> json) => _$PushTokenInputFromJson(json);
  
  final PushTokenInputProvider provider;
  final String token;

  Map<String, Object?> toJson() => _$PushTokenInputToJson(this);
}
