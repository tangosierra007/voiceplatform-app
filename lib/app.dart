import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/app_lock.dart';
import 'auth/links.dart';
import 'auth/version.dart';
import 'engine/engine_provider.dart';
import 'nav/call_flow.dart';
import 'nav/routes.dart';
import 'net/live_events.dart';
import 'theme/app_theme.dart';
import 'theme/theme_preference.dart';

class VoicePlatformApp extends ConsumerStatefulWidget {
  const VoicePlatformApp({super.key});

  @override
  ConsumerState<VoicePlatformApp> createState() => _VoicePlatformAppState();
}

class _VoicePlatformAppState extends ConsumerState<VoicePlatformApp> {
  @override
  void initState() {
    super.initState();
    // Minimum and recommended versions (APP7); quiet when offline.
    ref.read(appConfigProvider.notifier).check();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Registers the engine while signed in (SIP credentials into register()).
    ref.watch(engineSessionProvider);
    // Kept listening, so the audio routes are known when a call screen opens.
    ref.watch(audioStateProvider);
    final preference = ref.watch(themePreferenceProvider);
    return MaterialApp.router(
      title: 'VoicePlatform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: preference.mode,
      routerConfig: router,
      builder: (context, child) => SignInLinkListener(
        child: LiveEventsLifecycle(
          child: CallFlow(
            child: AppLock(
              location: () =>
                  router.routerDelegate.currentConfiguration.uri.path,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
