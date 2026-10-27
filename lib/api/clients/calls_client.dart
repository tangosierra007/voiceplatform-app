// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/caller_id.dart';
import '../models/post_calls_via_desk_phone_response.dart';
import '../models/via_desk_phone_input.dart';

part 'calls_client.g.dart';

@RestApi()
abstract class CallsClient {
  factory CallsClient(Dio dio, {String? baseUrl}) = _CallsClient;

  /// Numbers this user may present (AppKeypad picker), plus withheld when allowed
  @GET('/me/caller-ids')
  Future<List<CallerId>> getMeCallerIds();

  /// "Call from my desk phone instead" (AppMicrophone, A1).
  ///
  /// Rings the user's desk phone first; on answer the platform calls the number with the.
  /// chosen caller ID, through the same outbound checks as a desk phone call (caller ID,.
  /// toll fraud, barring). The app hands emergency numbers to the dialler before this; one.
  /// that arrives here is routed as an emergency call from the desk phone (CLAUDE.md.
  /// rule 8) and raises the `app_emergency_via_platform` alert. Audited.
  @POST('/calls/via-desk-phone')
  Future<PostCallsViaDeskPhoneResponse> postCallsViaDeskPhone({
    @Body() required ViaDeskPhoneInput body,
  });
}
