import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Signing out leaves no crash-report data behind: the scope (user, tags,
/// breadcrumbs) is cleared, and sentry-android's cache folder, where its
/// outbox and unsent envelopes wait (`<cacheDir>/sentry`), is deleted. The
/// SDK makes the folder again when it next needs it.
Future<void> clearDiagnosticsOnDevice({Directory? cacheDir}) async {
  try {
    await Sentry.configureScope((s) => s.clear());
  } catch (_) {
    // Not initialised (no DSN): nothing in memory.
  }
  try {
    final base = cacheDir ?? await getTemporaryDirectory();
    final sentry = Directory('${base.path}/sentry');
    if (await sentry.exists()) await sentry.delete(recursive: true);
  } catch (_) {
    // Nothing there, or not this platform.
  }
}
