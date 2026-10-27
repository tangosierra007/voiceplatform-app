// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/post_recordings_id_media_url_response.dart';
import '../models/recording_page.dart';

part 'recordings_client.g.dart';

@RestApi()
abstract class RecordingsClient {
  factory RecordingsClient(Dio dio, {String? baseUrl}) = _RecordingsClient;

  /// My recorded calls, last 90 days, by permission (AppMe "Recordings")
  @GET('/recordings')
  Future<RecordingPage> getRecordings({
    @Query('before') String? before,
    @Query('limit') int? limit = 50,
  });

  /// 5-minute signed URL; streamed, never saved on the device (APP8)
  @POST('/recordings/{id}/media-url')
  Future<PostRecordingsIdMediaUrlResponse> postRecordingsIdMediaUrl({
    @Path('id') required String id,
  });
}
