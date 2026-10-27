// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/greeting.dart';
import '../models/post_voicemail_greetings_kind_media_url_response.dart';
import '../models/post_voicemail_messages_id_media_url_response.dart';
import '../models/voicemail_box.dart';
import '../models/voicemail_greetings_kind.dart';
import '../models/voicemail_messages_id_read_request_body.dart';
import '../models/voicemail_messages_status.dart';
import '../models/voicemail_page.dart';
import '../models/voicemail_pin_request_body.dart';

part 'voicemail_client.g.dart';

@RestApi()
abstract class VoicemailClient {
  factory VoicemailClient(Dio dio, {String? baseUrl}) = _VoicemailClient;

  /// All, Mine and shared boxes with counts (AppVoicemail)
  @GET('/voicemail/boxes')
  Future<List<VoicemailBox>> getVoicemailBoxes();

  /// Messages, newest first
  @GET('/voicemail/messages')
  Future<VoicemailPage> getVoicemailMessages({
    @Query('status') VoicemailMessagesStatus? status = VoicemailMessagesStatus.all,
    @Query('limit') int? limit = 50,
    @Query('boxId') String? boxId,
    @Query('before') String? before,
  });

  /// 5-minute signed URL to stream one message (APP8); played, never saved
  @POST('/voicemail/messages/{id}/media-url')
  Future<PostVoicemailMessagesIdMediaUrlResponse> postVoicemailMessagesIdMediaUrl({
    @Path('id') required String id,
  });

  /// Mark heard or new; updates MWI
  @POST('/voicemail/messages/{id}/read')
  Future<void> postVoicemailMessagesIdRead({
    @Path('id') required String id,
    @Body() required VoicemailMessagesIdReadRequestBody body,
  });

  /// Delete by POST, audited, refused under legal hold (T12)
  @POST('/voicemail/messages/{id}/delete')
  Future<void> postVoicemailMessagesIdDelete({
    @Path('id') required String id,
  });

  /// My greetings (the "Greeting" link)
  @GET('/voicemail/greetings')
  Future<List<Greeting>> getVoicemailGreetings();

  /// Upload a greeting recorded in the app (WAV or M4A, up to 2 minutes, 5 MB)
  @PUT('/voicemail/greetings/{kind}')
  Future<Greeting> putVoicemailGreetingsKind({
    @Path('kind') required VoicemailGreetingsKind kind,
    @Body() required File body,
  });

  /// Back to the default greeting
  @DELETE('/voicemail/greetings/{kind}')
  Future<void> deleteVoicemailGreetingsKind({
    @Path('kind') required VoicemailGreetingsKind kind,
  });

  /// Signed URL to play my greeting back
  @POST('/voicemail/greetings/{kind}/media-url')
  Future<PostVoicemailGreetingsKindMediaUrlResponse> postVoicemailGreetingsKindMediaUrl({
    @Path('kind') required VoicemailGreetingsKind kind,
  });

  /// Change my voicemail PIN; audited, never logged
  @POST('/voicemail/pin')
  Future<void> postVoicemailPin({
    @Body() required VoicemailPinRequestBody body,
  });

  /// Streams the audio a signed URL names; needs the bearer token as well.
  ///
  /// Range requests supported. `Cache-Control: no-store`.
  @GET('/media/{token}')
  @DioResponseType(ResponseType.stream)
  Stream<String> getMediaToken({
    @Path('token') required String token,
  });
}
