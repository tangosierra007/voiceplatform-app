// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/call_settings.dart';
import '../models/call_settings_patch.dart';
import '../models/me.dart';
import '../models/office_hours.dart';
import '../models/override_input.dart';
import '../models/status.dart';
import '../models/status_input.dart';

part 'me_client.g.dart';

@RestApi()
abstract class MeClient {
  factory MeClient(Dio dio, {String? baseUrl}) = _MeClient;

  /// Who is signed in, and what they may do (AppMe header, tab gating)
  @GET('/me')
  Future<Me> getMe();

  /// Available, Do not disturb (optionally until a time), or Away (AppMe, A4).
  ///
  /// Synced with desk phones (DND as `*78`/`*79` and the phone-side state). Audited.
  @PUT('/me/status')
  Future<Status> putMeStatus({
    @Body() required StatusInput body,
  });

  /// "When I don't answer" (rings, timing, then voicemail)
  @GET('/me/call-settings')
  Future<CallSettings> getMeCallSettings();

  /// Change "When I don't answer"; same rules and audit as `PATCH /v1/me/call-settings`
  @PATCH('/me/call-settings')
  Future<CallSettings> patchMeCallSettings({
    @Body() required CallSettingsPatch body,
  });

  /// Business hours this user may override (AppMe "Office hours").
  ///
  /// Only time conditions where the tenant admin granted this user the override flag (APP11). Empty otherwise.
  @GET('/me/office-hours')
  Future<List<OfficeHours>> getMeOfficeHours();

  /// Open, Closed or Follow schedule; audited "via app" (APP11)
  @POST('/me/office-hours/{id}/override')
  Future<OfficeHours> postMeOfficeHoursIdOverride({
    @Path('id') required String id,
    @Body() required OverrideInput body,
  });
}
