// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/history_filter.dart';
import '../models/history_page.dart';
import '../models/history_seen_request_body.dart';

part 'history_client.g.dart';

@RestApi()
abstract class HistoryClient {
  factory HistoryClient(Dio dio, {String? baseUrl}) = _HistoryClient;

  /// Recents from CDRs (AppRecents).
  ///
  /// [mine] - "Mine only": calls to or from this extension, not its groups.
  @GET('/history')
  Future<HistoryPage> getHistory({
    @Query('before') String? before,
    @Query('filter') HistoryFilter? filter = HistoryFilter.all,
    @Query('mine') bool? mine = false,
    @Query('limit') int? limit = 50,
  });

  /// Clears the missed-call badge up to a time
  @POST('/history/seen')
  Future<void> postHistorySeen({
    @Body() required HistorySeenRequestBody body,
  });
}
