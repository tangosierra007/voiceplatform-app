// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';

import 'clients/signin_client.dart';
import 'clients/me_client.dart';
import 'clients/calls_client.dart';
import 'clients/device_client.dart';
import 'clients/directory_client.dart';
import 'clients/history_client.dart';
import 'clients/voicemail_client.dart';
import 'clients/recordings_client.dart';
import 'clients/messages_client.dart';
import 'clients/diagnostics_client.dart';

/// VoicePlatform app API `v0.1.0`.
///
/// The API the VoicePlatform phone and desktop apps call (spec 22). Contract owned by.
/// mobile-lead; WS1 builds it in `apps/api/src/app-api/`, WS4 generates the Dart client.
/// from it and runs `tool/mock_server` against it. A change goes through the lead only.
///
/// - Prefix `/app/v1`, separate from the portal's cookie-based `/v1` (decision 136, proposed).
///   Bearer access tokens only; no cookies are set or read, so the portal's Origin check (T10).
///   does not apply here and CSRF has nothing to ride on.
/// - Every authenticated route runs as the signed-in end user under RLS, with the same.
///   permission names as `/v1` (`packages/shared/src/permissions.ts`), and reuses the `/v1`.
///   services. Routes are thin (CLAUDE.md).
/// - Every request sends `X-VP-App: <platform>/<version>` (for example `android/1.0.3`).
///   Below the platform's minimum version every authenticated route answers 426.
///   `update_required` (APP7).
/// - Errors are `{ "error": code, "message": text }`, as `/v1`. A row outside the user's reach.
///   is 404, never 403 (RLS rejections map to 404, as `/v1`).
/// - Lists use cursor pagination: `?limit=` (1 to 100, default 50) and `?before=` the.
///   `nextBefore` of the previous page.
/// - Phone numbers are E.164. Times are RFC 3339 UTC.
/// - No SIP password appears in any response except `POST /devices/me/sip-credentials`, and.
///   none in any log (APP4, S1, S4). Phone contacts from the device never reach this API (APP12).
///
class AppApi {
  AppApi(
    Dio dio, {
    String? baseUrl,
  })  : _dio = dio,
        _baseUrl = baseUrl;

  final Dio _dio;
  final String? _baseUrl;

  static String get version => '0.1.0';

  SigninClient? _signin;
  MeClient? _me;
  CallsClient? _calls;
  DeviceClient? _device;
  DirectoryClient? _directory;
  HistoryClient? _history;
  VoicemailClient? _voicemail;
  RecordingsClient? _recordings;
  MessagesClient? _messages;
  DiagnosticsClient? _diagnostics;

  SigninClient get signin => _signin ??= SigninClient(_dio, baseUrl: _baseUrl);

  MeClient get me => _me ??= MeClient(_dio, baseUrl: _baseUrl);

  CallsClient get calls => _calls ??= CallsClient(_dio, baseUrl: _baseUrl);

  DeviceClient get device => _device ??= DeviceClient(_dio, baseUrl: _baseUrl);

  DirectoryClient get directory => _directory ??= DirectoryClient(_dio, baseUrl: _baseUrl);

  HistoryClient get history => _history ??= HistoryClient(_dio, baseUrl: _baseUrl);

  VoicemailClient get voicemail => _voicemail ??= VoicemailClient(_dio, baseUrl: _baseUrl);

  RecordingsClient get recordings => _recordings ??= RecordingsClient(_dio, baseUrl: _baseUrl);

  MessagesClient get messages => _messages ??= MessagesClient(_dio, baseUrl: _baseUrl);

  DiagnosticsClient get diagnostics => _diagnostics ??= DiagnosticsClient(_dio, baseUrl: _baseUrl);
}
