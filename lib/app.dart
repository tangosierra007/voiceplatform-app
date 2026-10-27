import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nav/call_flow.dart';
import 'nav/routes.dart';
import 'net/live_events.dart';
import 'theme/app_theme.dart';
import 'theme/theme_preference.dart';

class VoicePlatformApp extends ConsumerWidget {
  const VoicePlatformApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final preference = ref.watch(themePreferenceProvider);
    return MaterialApp.router(
      title: 'VoicePlatform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: preference.mode,
      routerConfig: router,
      builder: (context, child) => LiveEventsLifecycle(
        child: CallFlow(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
