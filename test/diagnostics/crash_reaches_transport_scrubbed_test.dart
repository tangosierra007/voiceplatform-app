import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:voiceplatform_app/diagnostics/diagnostics.dart';

/// Records the bytes of every envelope, exactly as they would go on the wire.
class RecordingTransport implements Transport {
  RecordingTransport(this.options);
  final SentryOptions options;
  final sent = <String>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final bytes = <int>[];
    await for (final chunk in envelope.envelopeStream(options)) {
      bytes.addAll(chunk);
    }
    sent.add(utf8.decode(bytes, allowMalformed: true));
    return SentryId.newId();
  }
}

// APP9 and APP12, end to end: a crash carrying a fake password, token, code,
// email, phone number and contact goes through the real SDK pipeline with the
// app's settings, and what reaches the transport is scrubbed.
void main() {
  const password = 'fakeSipPassw0rd-xyz';
  // Built at run time so the secret scan doesn't take the fake for a real one.
  final token = ['vp', 'rt', List.generate(32, (i) => '9b8c7d6e5f4a'[i % 12]).join()].join('_');
  const code = '482913';
  const email = 'ava.nguyen@example.com';
  const phone = '0491 570 737';
  const contactName = 'Mia Thompson';

  late RecordingTransport recorder;
  final scrubber = DiagnosticsScrubber()..addSecret(password);

  setUp(() async {
    scrubber.rememberAddressBookValues([contactName]);
    late SentryOptions opts;
    await Sentry.init((o) {
      opts = o;
      o.dsn = 'https://public@glitchtip.example.invalid/1';
      o.release = Diagnostics.release('1.0.0', '42');
      o.environment = 'dev';
      recorder = RecordingTransport(o);
      o.transport = recorder;
      Diagnostics.applyPrivacy(o, scrubber);
    });
    Diagnostics.installScrubbingTransport(opts, scrubber);
  });

  tearDown(() async {
    await Sentry.close();
    scrubber.forgetAddressBookValues();
  });

  test('a crash reaches the transport scrubbed', () async {
    Sentry.addBreadcrumb(Breadcrumb(category: 'auth', message: 'refresh with refresh_token=$token for $email'));
    Sentry.addBreadcrumb(Breadcrumb(category: 'contacts', message: 'loaded $contactName $phone'));
    await Sentry.configureScope((scope) async {
      await scope.setContexts('call', {'remote': phone, 'contacts': [contactName]});
      await scope.setTag('code', code);
      scope.addAttachment(
        SentryAttachment.fromIntList(
          utf8.encode('Authorization: Digest response="ab12"\npassword=$password\ncode $code'),
          'engine.log',
          contentType: 'text/plain',
        ),
      );
      scope.addAttachment(SentryAttachment.fromIntList([0, 1, 2], 'screen.png', contentType: 'image/png'));
    });

    try {
      throw StateError('sign-in failed: password=$password token=$token code $code for $email at $phone ($contactName)');
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
    }

    expect(recorder.sent, hasLength(1));
    final wire = recorder.sent.single;
    expect(wire, contains('"type":"event"'));
    expect(wire, contains('StateError'));
    expect(wire, contains('voiceplatform-app@1.0.0+42'));
    for (final secret in [password, token, code, email, contactName, 'ab12', '0491', '570 737']) {
      expect(wire, isNot(contains(secret)), reason: secret);
    }
    // No 6-digit run in any text: SDK numbers (memory sizes), hex ids and\n    // timestamps aside.\n    final text = wire\n        .replaceAll(RegExp(r':-?\d+(\.\d+)?(?=[,}\]])'), ':0')\n        .replaceAll(RegExp(r'"[0-9a-f]{16,32}"'), '"id"')\n        .replaceAll(RegExp(r'\d{4}-\d\d-\d\dT[\d:.]+Z?'), 'time');\n    expect(RegExp(r'\d(?:[ ()\-./]{0,2}\d){5,}').firstMatch(text)?[0], isNull);
    expect(wire, contains('engine.log'));
    expect(wire, isNot(contains('screen.png')));
    expect(wire, isNot(contains('"user"')));
    expect(wire, isNot(contains('"category":"contacts"')));
  });

  test('no PII defaults', () {
    final o = SentryFlutterOptions();
    Diagnostics.applyPrivacy(o, scrubber);
    Diagnostics.applyFlutterPrivacy(o);
    expect(o.sendDefaultPii, isFalse);
    expect(o.attachScreenshot, isFalse);
    expect(o.attachViewHierarchy, isFalse);
    expect(o.enableUserInteractionBreadcrumbs, isFalse);
    expect(o.enableNativeCrashHandling, isFalse);
    expect(o.anrEnabled, isFalse);
    expect(o.enableAutoNativeBreadcrumbs, isFalse);
  });

  test('off without a DSN (debug and test builds)', () {
    expect(Diagnostics.dsn, isEmpty);
    expect(Diagnostics.enabled, isFalse);
    expect(Diagnostics.environment, 'dev');
  });
}
