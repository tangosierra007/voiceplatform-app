import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceplatform_app/app.dart';
import 'package:voiceplatform_app/engine/engine_provider.dart';
import 'package:voiceplatform_app/engine/fake_call_engine.dart';
import 'package:voiceplatform_app/net/events.dart';
import 'package:voiceplatform_app/net/live_events.dart';
import 'package:voiceplatform_app/shell/shell_status.dart';
import 'package:voiceplatform_app/theme/theme_preference.dart';

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
}) async {
  SharedPreferences.setMockInitialValues({
    if (theme != ThemePreference.system)
      ThemePreferenceNotifier.storageKey: theme.name,
  });
  final sp = await SharedPreferences.getInstance();
  final e = engine ?? FakeCallEngine(outgoing: OutgoingScript.manual);
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      shellStatusProvider.overrideWithValue(status),
      callEngineProvider.overrideWithValue(e),
      liveEventsProvider.overrideWithValue(live ?? quietLiveEvents()),
    ],
    child: const VoicePlatformApp(),
  );
}

/// Live events with no network: the stream opens and stays silent.
LiveEvents quietLiveEvents() => LiveEvents(
  connect: () => StreamController<ServerEvent>().stream,
  poll: (_) async => (items: null, etag: null),
);
