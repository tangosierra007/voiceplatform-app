// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/device_summary.dart';
import '../models/me_devices_id_request_body.dart';
import '../models/push_token_input.dart';
import '../models/sip_credentials.dart';

part 'device_client.g.dart';

@RestApi()
abstract class DeviceClient {
  factory DeviceClient(Dio dio, {String? baseUrl}) = _DeviceClient;

  /// Signed-in devices and desk phones (AppMe, DeskDevices)
  @GET('/me/devices')
  Future<List<DeviceSummary>> getMeDevices();

  /// Rings switch for an app or desktop device (A3)
  @PATCH('/me/devices/{id}')
  Future<DeviceSummary> patchMeDevicesId({
    @Path('id') required String id,
    @Body() required MeDevicesIdRequestBody body,
  });

  /// Sign out another of my app or desktop devices; audited
  @POST('/me/devices/{id}/sign-out')
  Future<void> postMeDevicesIdSignOut({
    @Path('id') required String id,
  });

  /// This device's SIP identity, for CallEngine.register only.
  ///
  /// The only response carrying a SIP password (APP4). POST so nothing caches it; the app.
  /// keeps it in memory and the Keystore, never in logs or GlitchTip. Refused for Basic.
  /// (APP3), a revoked device (401) and below the minimum version (426, APP7). Calling it.
  /// again rotates the password and drops the old registration.
  @POST('/devices/me/sip-credentials')
  Future<SipCredentials> postDevicesMeSipCredentials();

  /// Store or replace this device's FCM token (APNs later)
  @PUT('/devices/me/push-token')
  Future<void> putDevicesMePushToken({
    @Body() required PushTokenInput body,
  });

  /// Sign out this device (AppMe "Sign out"); revokes tokens and SIP identity
  @POST('/devices/me/sign-out')
  Future<void> postDevicesMeSignOut();
}
