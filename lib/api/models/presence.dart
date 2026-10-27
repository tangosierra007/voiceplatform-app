// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

/// Dots: green available and mobile_only, orange on_call, red dnd, grey away and offline
@JsonEnum()
enum Presence {
  @JsonValue('available')
  available('available'),
  @JsonValue('on_call')
  onCall('on_call'),
  @JsonValue('dnd')
  dnd('dnd'),
  @JsonValue('away')
  away('away'),
  @JsonValue('offline')
  offline('offline'),
  @JsonValue('mobile_only')
  mobileOnly('mobile_only'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const Presence(this.json);

  factory Presence.fromJson(String json) => values.firstWhere(
        (e) => e.json == json,
        orElse: () => $unknown,
      );

  final String? json;
  String toJson() {
    final value = json;
    if (value == null) {
      throw StateError('Cannot convert enum value with null JSON representation to String. '
          'This usually happens for \$unknown or @JsonValue(null) entries.');
    }
    return value as String;
  }

  @override
  String toString() => json?.toString() ?? super.toString();
  /// Returns all defined enum values excluding the $unknown value.
  static List<Presence> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
