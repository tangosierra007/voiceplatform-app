import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/app.dart';
import 'package:voiceplatform_app/calls/call_actions.dart';
import 'package:voiceplatform_app/calls/directory.dart';
import 'package:voiceplatform_app/calls/me_state.dart';
import 'package:voiceplatform_app/auth/app_lock.dart';
import 'package:voiceplatform_app/auth/auth.dart';
import 'package:voiceplatform_app/auth/links.dart';
import 'package:voiceplatform_app/auth/session_store.dart';
import 'package:voiceplatform_app/auth/version.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/platform/device_keys.dart';
import 'package:voiceplatform_app/platform/phone.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/features/recents/greetings.dart';
import 'package:voiceplatform_app/features/recents/media_player.dart';
import 'package:voiceplatform_app/features/recents/recents_data.dart';
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import '../../tool/mock_server/fixtures.dart' as fx;
import 'call_fakes.dart';
import 'fake_api.dart';
import 'fakes.dart';

export 'call_fakes.dart';
export 'fake_api.dart';
export 'fakes.dart';

/// The badges and lines the artboards show: Recents 2, Messages 1.
const artboardStatus = ShellStatus(
  recentsBadge: 2,
  messagesBadge: 1,
  hasSmsLine: true,
);

/// The whole app with no network: fixed shell status and a FakeCallEngine.
/// [theme] is stored the way the Me switch stores it.
Future<Widget> appUnderTest({
  ShellStatus status = artboardStatus,
  CallEngine? engine,
  ThemePreference theme = ThemePreference.system,
  LiveEvents? live,
  AuthState auth = const SignedIn('60000000-0000-4000-8000-000000000001'),
  ScriptedAuth? authController,

  /// The real AuthController (empty session store, fake key, no network).
  bool realAuth = false,
  AppConfig? updateRequired,
  AppConfig? config,
  FakePhone? phone,
  FakeBiometrics? biometrics,
  bool biometricUnlock = false,
  PendingSignIn? pending,
  DateTime Function()? clock,
  Stream<Uri>? links,
  String appVersion = '1.0.0',
  Map<String, Object> prefs = const {},
  FakeMic? mic,
  List<PhoneContact> phoneContacts = const [],
  bool offline = false,
  DeskPhoneCall? deskPhone,
  EngineUi? ui,
  StatusStatus myStatus = StatusStatus.available,
  FakeMediaPlayer? player,
  FixedPhoneContacts? phoneSource,
  Future<void> Function()? onHistorySeen,
  FakeApi? api,
  String? accessToken,
  void Function(Iterable<String>)? addressBook,
}) async {
  SharedPreferences.setMockInitialValues({
    if (theme != ThemePreference.system)
      ThemePreferenceNotifier.storageKey: theme.name,
    if (biometricUnlock) BiometricUnlockNotifier.storageKey: true,
    ...prefs,
  });
  final sp = await SharedPreferences.getInstance();
  final e = engine ?? FakeCallEngine(outgoing: OutgoingScript.manual);
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      shellStatusProvider.overrideWithValue(status),
      callEngineProvider.overrideWithValue(e),
      liveEventsProvider.overrideWithValue(live ?? quietLiveEvents()),
      if (!realAuth)
        authProvider.overrideWith(() => authController ?? ScriptedAuth(auth)),
      appConfigProvider.overrideWith(() => NoConfigCheck(config)),
      if (updateRequired != null)
        updateRequiredProvider.overrideWith(
          () => PresetUpdateRequired(updateRequired),
        ),
      phoneLauncherProvider.overrideWithValue(phone ?? FakePhone()),
      biometricsProvider.overrideWithValue(biometrics ?? FakeBiometrics()),
      deviceKeysProvider.overrideWithValue(FakeDeviceKeys()),
      sessionStoreProvider.overrideWithValue(MemorySessionStore()),
      incomingLinksProvider.overrideWithValue(links ?? const Stream.empty()),
      apiConfigProvider.overrideWithValue(
        ApiConfig(
          baseUrl: 'http://127.0.0.1:9/app/v1',
          platform: 'android',
          appVersion: appVersion,
          deviceModel: 'Pixel 8',
        ),
      ),
      if (clock != null) clockProvider.overrideWithValue(clock),
      if (api != null)
        dioProvider.overrideWith(
          (ref) => Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9/app/v1'))
            ..httpClientAdapter = api
            ..interceptors.add(
              AppHeadersInterceptor(
                appHeader: 'android/$appVersion',
                accessToken: () => ref.read(accessTokenProvider),
              ),
            ),
        ),
      if (accessToken != null)
        accessTokenProvider.overrideWith(() => _PresetToken(accessToken)),
      micPermissionProvider.overrideWithValue(mic ?? FakeMic()),
      if (ui != null) engineUiProvider.overrideWithValue(ui),
      deskPhoneCallProvider.overrideWithValue(
        deskPhone ?? (n, id) async => 'Desk phone 202',
      ),
      phoneContactsSourceProvider.overrideWithValue(
        phoneSource ?? FixedPhoneContacts(phoneContacts),
      ),
      addressBookScrubberProvider.overrideWithValue(addressBook ?? (_) {}),
      colleagueDirectoryProvider.overrideWith(
        (ref) async => fixtureDirectory(now: clock?.call()),
      ),
      colleaguesProvider.overrideWith(
        (ref) async => fixtureColleagues(now: clock?.call()),
      ),
      teamsProvider.overrideWith((ref) async => fixtureTeams()),
      meProvider.overrideWith(
        (ref) async => Me.fromJson(fx.me(status: myStatus.json!)),
      ),
      historyProvider.overrideWith(
        (ref, f) async => fixtureHistory(
          filter: switch (f) {
            RecentsFilter.missed => 'missed',
            RecentsFilter.voicemail => 'voicemail',
            _ => 'all',
          },
          mine: f == RecentsFilter.mine,
        ),
      ),
      markHistorySeenProvider.overrideWithValue(onHistorySeen ?? () async {}),
      voicemailBoxesProvider.overrideWith((ref) async => fixtureBoxes()),
      voicemailMessagesProvider.overrideWith(
        (ref, box) async => fixtureVoicemails(box: box),
      ),
      greetingsProvider.overrideWith((ref) async => fixtureGreetings()),
      mediaPlayerProvider.overrideWithValue(player ?? FakeMediaPlayer()),
      sharedContactsProvider.overrideWith((ref) async => fixtureShared()),
      callerIdsProvider.overrideWith((ref) async => fixtureCallerIds()),
      myStatusProvider.overrideWith(() => PresetStatus(myStatus)),
      if (offline) offlineProvider.overrideWith(PresetOffline.new),
      if (pending != null)
        pendingSignInProvider.overrideWith(() => PresetPending(pending)),
    ],
    child: const VoicePlatformApp(),
  );
}

/// Live events with no network: the stream opens and stays silent.
LiveEvents quietLiveEvents() => LiveEvents(
  connect: () => StreamController<ServerEvent>().stream,
  poll: (_) async => (items: null, etag: null),
);

class _PresetToken extends AccessTokenNotifier {
  _PresetToken(this.token);
  final String token;

  @override
  String? build() => token;
}
