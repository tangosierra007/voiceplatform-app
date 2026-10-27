import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Sentry's NDK crash capture must stay off: native events would bypass the
// Dart scrubber (APP9). sentry_flutter's enableNativeCrashHandling=false only
// stops the Kotlin handler and ANR, so the manifest turns the NDK off. CI also
// checks the merged release manifest.
void main() {
  test('the app manifest turns off Sentry NDK crash capture', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final meta = RegExp(
      r'<meta-data\s+android:name="io\.sentry\.ndk\.enable"\s+android:value="false"\s*/>',
    );
    expect(meta.hasMatch(manifest), isTrue);
  });
}
