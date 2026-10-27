// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/message.dart';
import '../models/message_page.dart';
import '../models/send_input.dart';
import '../models/sms_line.dart';
import '../models/thread_page.dart';

part 'messages_client.g.dart';

@RestApi()
abstract class MessagesClient {
  factory MessagesClient(Dio dio, {String? baseUrl}) = _MessagesClient;

  /// Mobile lines this user may text from (filter chips; Messages tab hidden if empty)
  @GET('/messages/lines')
  Future<List<SmsLine>> getMessagesLines();

  /// Conversations across my lines, newest first (AppMessages)
  @GET('/messages/threads')
  Future<ThreadPage> getMessagesThreads({
    @Query('limit') int? limit = 50,
    @Query('lineId') String? lineId,
    @Query('before') String? before,
  });

  /// One conversation (AppThread)
  @GET('/messages/threads/{id}/messages')
  Future<MessagePage> getMessagesThreadsIdMessages({
    @Path('id') required String id,
    @Query('before') String? before,
    @Query('limit') int? limit = 50,
  });

  /// Mark a conversation read
  @POST('/messages/threads/{id}/read')
  Future<void> postMessagesThreadsIdRead({
    @Path('id') required String id,
  });

  /// Send a text from a line (reply box, "From Sales mobile 0491 571 266").
  ///
  /// Same checks as `POST /v1/me/sms/lines/:lineId/messages` (GW rules, `sms.send`).
  @POST('/messages/send')
  Future<Message> postMessagesSend({
    @Body() required SendInput body,
  });
}
