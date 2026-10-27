// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'call_settings_ring_devices.dart';
import 'call_settings_then_to.dart';

part 'call_settings.g.dart';

@JsonSerializable()
class CallSettings {
  const CallSettings({
    required this.ringDevices,
    required this.ringSeconds,
    required this.thenTo,
    this.followMeTo,
    this.followMeSeconds,
    this.followMeConfirm,
    this.forwardAlwaysTo,
  });
  
  factory CallSettings.fromJson(Map<String, Object?> json) => _$CallSettingsFromJson(json);
  
  /// What rings first, for the summary "Desk phone and app 15 s, then voicemail"
  final List<CallSettingsRingDevices> ringDevices;
  final int ringSeconds;

  /// E.164, rung after ringSeconds when set
  final String? followMeTo;
  final int? followMeSeconds;
  final bool? followMeConfirm;
  final CallSettingsThenTo thenTo;

  /// E.164 or extension; null when off
  final String? forwardAlwaysTo;

  Map<String, Object?> toJson() => _$CallSettingsToJson(this);
}
