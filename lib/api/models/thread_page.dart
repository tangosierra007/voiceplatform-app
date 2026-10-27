// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'thread.dart';

part 'thread_page.g.dart';

@JsonSerializable()
class ThreadPage {
  const ThreadPage({
    required this.items,
    required this.unreadTotal,
    this.nextBefore,
  });
  
  factory ThreadPage.fromJson(Map<String, Object?> json) => _$ThreadPageFromJson(json);
  
  final List<Thread> items;
  final String? nextBefore;
  final int unreadTotal;

  Map<String, Object?> toJson() => _$ThreadPageToJson(this);
}
