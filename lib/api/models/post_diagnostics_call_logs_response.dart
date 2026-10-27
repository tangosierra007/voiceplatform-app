// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'post_diagnostics_call_logs_response.g.dart';

@JsonSerializable()
class PostDiagnosticsCallLogsResponse {
  const PostDiagnosticsCallLogsResponse({
    required this.reference,
  });
  
  factory PostDiagnosticsCallLogsResponse.fromJson(Map<String, Object?> json) => _$PostDiagnosticsCallLogsResponseFromJson(json);
  
  final String reference;

  Map<String, Object?> toJson() => _$PostDiagnosticsCallLogsResponseToJson(this);
}
