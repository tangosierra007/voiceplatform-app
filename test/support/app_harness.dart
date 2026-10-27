import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/app.dart';
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
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

import 'fakes.dart';

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
