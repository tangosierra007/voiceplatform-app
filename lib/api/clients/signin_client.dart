// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/app_config.dart';
import '../models/auth_email_requests_request_id_resend_request_body.dart';
import '../models/auth_licence_requests_request_body.dart';
import '../models/complete_input.dart';
import '../models/email_request_accepted.dart';
import '../models/email_request_input.dart';
import '../models/platform.dart';
import '../models/qr_complete_input.dart';
import '../models/refresh_input.dart';
import '../models/session.dart';
import '../models/tokens.dart';

part 'signin_client.g.dart';

@RestApi()
abstract class SigninClient {
  factory SigninClient(Dio dio, {String? baseUrl}) = _SigninClient;

  /// Minimum and recommended app versions (AppUpdate)
  @GET('/config')
  Future<AppConfig> getConfig({
    @Query('platform') required Platform platform,
  });

  /// Start sign-in by email (AppSignIn).
  ///
  /// The app generates a 32-byte request secret, keeps it in memory, and sends it here. The.
  /// email holds a link and a 6-digit code, both tied to this request; completing needs the.
  /// secret, so a forwarded link is useless (APP1). Same 202 whether or not the email exists,.
  /// is an end user, or is Advanced (APP2). Rate limited per email and per IP (429).
  @POST('/auth/email-requests')
  Future<EmailRequestAccepted> postAuthEmailRequests({
    @Body() required EmailRequestInput body,
  });

  /// Send again (AppCode timer)
  @POST('/auth/email-requests/{requestId}/resend')
  Future<EmailRequestAccepted> postAuthEmailRequestsRequestIdResend({
    @Path('requestId') required String requestId,
    @Body() required AuthEmailRequestsRequestIdResendRequestBody body,
  });

  /// Finish sign-in with the code or the link token, and bind this device.
  ///
  /// Exactly one of `code` or `linkToken`. Single use, 10 minutes, the request locks after.
  /// 5 wrong codes (APP1). Refused for Basic extensions with 403 `licence_basic` (APP3). The.
  /// device's public key (Android Keystore, P-256) is bound to the refresh token. A user.
  /// already at 5 app and desktop devices gets 409 `device_limit` (A3).
  @POST('/auth/email-requests/{requestId}/complete')
  Future<Session> postAuthEmailRequestsRequestIdComplete({
    @Path('requestId') required String requestId,
    @Body() required CompleteInput body,
  });

  /// Sign in from the QR on the end user portal ("Scan the QR code instead").
  ///
  /// The portal's "Sign in the VoicePlatform app" QR (new `POST /v1/me/app-qr`, WS1 1.1) holds.
  /// `vpapp://signin/<qrToken>`: 32 random bytes, SHA-256 stored, single use, 10 minutes,.
  /// refused for Basic at generation and here.
  @POST('/auth/qr/complete')
  Future<Session> postAuthQrComplete({
    @Body() required QrCompleteInput body,
  });

  /// New access token; rotates the refresh token.
  ///
  /// Signed with the device key. Re-checks the licence (APP3), the device's revocation and.
  /// the minimum version. Reuse of an old refresh token revokes the device.
  @POST('/auth/refresh')
  Future<Tokens> postAuthRefresh({
    @Body() required RefreshInput body,
  });

  /// "Ask my admin to upgrade" (AppBasic, A6).
  ///
  /// Carries the `refusalToken` from a `licence_basic` refusal (single use, 1 hour). Notifies.
  /// the tenant admins in the portal and by email, linking to the extension's licence.
  /// setting. One open request per extension; a repeat answers 202 without a new email.
  /// Audited `app.licence_requested`.
  @POST('/auth/licence-requests')
  Future<void> postAuthLicenceRequests({
    @Body() required AuthLicenceRequestsRequestBody body,
  });
}
