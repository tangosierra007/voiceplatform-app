// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'counts.dart';
import 'history_entry.dart';

part 'history_page.g.dart';

@JsonSerializable()
class HistoryPage {
  const HistoryPage({
    required this.items,
    required this.counts,
    this.nextBefore,
  });
  
  factory HistoryPage.fromJson(Map<String, Object?> json) => _$HistoryPageFromJson(json);
  
  final List<HistoryEntry> items;
  final String? nextBefore;
  final Counts counts;

  Map<String, Object?> toJson() => _$HistoryPageToJson(this);
}
