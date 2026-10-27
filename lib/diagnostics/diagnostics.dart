import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'scrubber.dart';

export 'scrubber.dart';

/// Crash and error reporting to the self-hosted GlitchTip through
/// `sentry_flutter` (spec 22 Diagnostics, decision 140; APP9, APP12).
///
/// Off unless the build passes `--dart-define=SENTRY_DSN=...` (CI does so for
/// release builds only, from the `SENTRY_DSN` secret). Debug and test builds
/// have no DSN, so nothing is set up and nothing is sent.
///
/// Everything leaving the device is scrubbed by [DiagnosticsScrubber] twice:
/// in `beforeSend` / `beforeBreadcrumb`, and again on the finished envelope in
/// [ScrubbingTransport] (which also covers attachments added to the scope).
/// Native (Kotlin and C) crash capture is off: those events would bypass the
/// Dart scrubber.
abstract final class Diagnostics {
  static const dsn = String.fromEnvironment('SENTRY_DSN');
  static const _env = String.fromEnvironment('VP_ENV', defaultValue: 'dev');

  /// `dev` or `prod` (from `--dart-define=VP_ENV`); anything else is `dev`.
  static String get environment => _env == 'prod' ? 'prod' : 'dev';

  static bool get enabled => dsn.isNotEmpty;

  /// `voiceplatform-app@<versionName>+<versionCode>`.
  static String release(String versionName, String versionCode) =>
      'voiceplatform-app@$versionName+$versionCode';

  /// Starts Sentry when a DSN is built in; otherwise does nothing.
  static Future<void> init({required String versionName, required String versionCode}) async {
    if (!enabled) return;
    SentryFlutterOptions? opts;
    await SentryFlutter.init((o) {
      opts = o;
      o.dsn = dsn;
      o.release = release(versionName, versionCode);
      o.environment = environment;
      o.dist = versionCode;
      applyPrivacy(o, DiagnosticsScrubber.instance);
      applyFlutterPrivacy(o);
    });
    final o = opts;
    if (o != null) installScrubbingTransport(o, DiagnosticsScrubber.instance);
  }

  /// No PII defaults and the scrubber callbacks. Fails closed: an event or
  /// breadcrumb the scrubber can't process is dropped.
  static void applyPrivacy(SentryOptions o, DiagnosticsScrubber scrubber) {
    o.sendDefaultPii = false;
    o.attachThreads = false;
    o.tracesSampleRate = null;
    o.beforeSend = (event, hint) {
      try {
        _scrubHintAttachments(hint, scrubber);
        return SentryEvent.fromJson(scrubber.scrubEventJson(event.toJson()));
      } catch (_) {
        return null;
      }
    };
    o.beforeBreadcrumb = (breadcrumb, hint) {
      if (breadcrumb == null) return null;
      try {
        final b = scrubber.scrubBreadcrumbJson(breadcrumb.toJson());
        return b == null ? null : Breadcrumb.fromJson(b);
      } catch (_) {
        return null;
      }
    };
    // Not used by the app: transactions, feedback and logs are dropped.
    o.beforeSendTransaction = (_, _) => null;
    o.beforeSendFeedback = (_, _) => null;
    o.beforeSendLog = (_, _) => null;
  }

  /// Flutter and native options: no screenshots, no view hierarchy, no
  /// widget or native breadcrumbs, no native crash, ANR or session capture.
  static void applyFlutterPrivacy(SentryFlutterOptions o) {
    o.attachScreenshot = false;
    o.attachViewHierarchy = false;
    o.reportViewHierarchyIdentifiers = false;
    o.enableUserInteractionBreadcrumbs = false;
    o.enableUserInteractionTracing = false;
    o.enableAutoNativeBreadcrumbs = false;
    o.enableNativeCrashHandling = false;
    o.enableNdkScopeSync = false;
    o.anrEnabled = false;
    o.enableTombstone = false;
    o.enableAutoSessionTracking = false;
    o.enableAutoPerformanceTracing = false;
    o.enableFramesTracking = false;
    o.reportPackages = false;
  }

  /// Wraps the transport chosen by the SDK so every envelope is scrubbed
  /// last, whatever added to it.
  static void installScrubbingTransport(SentryOptions o, DiagnosticsScrubber scrubber) {
    if (o.transport is! ScrubbingTransport) {
      o.transport = ScrubbingTransport(o.transport, scrubber);
    }
  }

  static void _scrubHintAttachments(Hint hint, DiagnosticsScrubber scrubber) {
    // Attachment bytes load lazily; ScrubbingTransport scrubs or drops each
    // one when the envelope is built. Address-book files go at once.
    hint.attachments.removeWhere((a) => DiagnosticsScrubber.addressBookKey.hasMatch(a.filename));
  }
}

/// The last gate before the SDK's own transport (HTTP, or the native SDK's
/// on-disk queue): events are scrubbed again as JSON, text attachments are
/// scrubbed, other attachments and every other item type are dropped.
final class ScrubbingTransport implements Transport {
  ScrubbingTransport(this.inner, this._scrubber);

  final Transport inner;
  final DiagnosticsScrubber _scrubber;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final items = <SentryEnvelopeItem>[];
    for (final item in envelope.items) {
      final type = item.header.type;
      try {
        if (type == 'event') {
          final json = jsonDecode(utf8.decode(await item.dataFactory())) as Map<String, dynamic>;
          final bytes = utf8.encode(jsonEncode(_scrubber.scrubEventJson(json)));
          items.add(SentryEnvelopeItem(item.header, () => bytes));
        } else if (type == 'attachment') {
          final bytes = _scrubber.scrubAttachment(
            filename: item.header.fileName ?? '',
            contentType: item.header.contentType,
            bytes: await item.dataFactory(),
          );
          if (bytes != null) items.add(SentryEnvelopeItem(item.header, () => bytes));
        } else if (type == 'client_report') {
          items.add(item);
        }
      } catch (e) {
        // Fail closed: an item that can't be scrubbed isn't sent.
        if (kDebugMode) debugPrint('diagnostics: dropped a $type item ($e)');
      }
    }
    if (items.isEmpty) return null;
    return inner.send(
      SentryEnvelope(envelope.header, items, containsUnhandledException: envelope.containsUnhandledException),
    );
  }
}
