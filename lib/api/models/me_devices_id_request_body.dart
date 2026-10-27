// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'me_devices_id_request_body.g.dart';

@JsonSerializable()
class MeDevicesIdRequestBody {
  const MeDevicesIdRequestBody({
    required this.rings,
  });
  
  factory MeDevicesIdRequestBody.fromJson(Map<String, Object?> json) => _$MeDevicesIdRequestBodyFromJson(json);
  
  final bool rings;

  Map<String, Object?> toJson() => _$MeDevicesIdRequestBodyToJson(this);
}
