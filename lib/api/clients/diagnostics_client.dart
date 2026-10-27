// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/post_diagnostics_call_logs_response.dart';

part 'diagnostics_client.g.dart';

@RestApi()
abstract class DiagnosticsClient {
  factory DiagnosticsClient(Dio dio, {String? baseUrl}) = _DiagnosticsClient;

  /// "Send call logs to support": the scrubbed engine log for the last call.
  ///
  /// Gzipped text, up to 2 MB, already scrubbed on the device (APP9); the API scrubs again.
  /// before storing in object storage for 30 days, visible to platform and reseller support.
  /// for this tenant. Audited. Answers with a reference to quote to support.
  @POST('/diagnostics/call-logs')
  Future<PostDiagnosticsCallLogsResponse> postDiagnosticsCallLogs({
    @Body() required File body,
  });
}
