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
  ///
  /// [number] - "Calls with this number": only the entries whose `number` (the other party) is this one, with the other filters and the cursor as usual; the badge counts don't change. Normalised to E.164 first, as the entries store it: `+61491570156`, `+61 0491 570 156`, `61491570156` and `0491 570 156` are the same number, and so are `0355501200` and `+61355501200`; 13, 1300 and 1800 numbers become `+6113…`, `+611300…` and `+611800…`; international as `+<country>` or `0011<country>`. Spaces, dots, dashes and brackets are ignored. Private callers (`anonymous`) never match. Anything else (an extension, a short code, 000, an 8-digit local number, `anonymous`) is a 400 `validation_error`.
  @GET('/history')
  Future<HistoryPage> getHistory({
    @Query('number') String? number,
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
