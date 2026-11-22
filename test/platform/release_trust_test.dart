import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// G8: only a debug build may trust an extra CA, never release or profile
// (spec 22, S1). These check the sources; the vpCheckReleaseNoTestCa and
// vpCheckProfileNoTestCa Gradle tasks check each built APK or bundle (they
// run after every release build, CI's included).
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('release and profile manifests set no network security config', () {
    for (final path in [
      'android/app/src/main/AndroidManifest.xml',
      'android/app/src/profile/AndroidManifest.xml',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('networkSecurityConfig')),
        reason: path,
      );
    }
  });

  test('only the debug source set has network security configs', () {
    for (final dir in ['android/app/src/main', 'android/app/src/profile']) {
      final hits = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.contains('network_security_config') ||
                f.path.contains('vp_test_ca'),
          )
          .map((f) => f.path)
          .toList();
      expect(hits, isEmpty, reason: dir);
    }
    expect(Directory('android/app/src/release').existsSync(), isFalse);
  });

  test('the committed debug config trusts no extra CA', () {
    final debug = File(
      'android/app/src/debug/res/xml/network_security_config.xml',
    ).readAsStringSync();
    expect(debug, isNot(contains('trust-anchors')));
    expect(debug, isNot(contains('certificates')));
  });

  test('the test CA config is outside every resource folder', () {
    final template = File(
      'android/app/test-ca/network_security_config_test_ca.xml',
    ).readAsStringSync();
    expect(template, contains('<certificates src="@raw/vp_test_ca"/>'));
    expect(template, contains('<certificates src="system"/>'));
  });

  test('the test CA resources are generated for the debug build type only', () {
    final generated = RegExp(
      r'onVariants\(selector\(\)\.withBuildType\("debug"\)\)[^\n]*\n'
      r'\s*val pem = vpTestCaPem \?: return@onVariants',
    );
    expect(generated.hasMatch(gradle), isTrue);
    expect(RegExp(r'register<VpTestCaResources>').allMatches(gradle).length, 1);
    expect(RegExp(r'addGeneratedSourceDirectory').allMatches(gradle).length, 1);
  });

  test('release and profile builds are checked for the test CA', () {
    expect(gradle, contains('listOf("release", "profile")'));
    expect(gradle, contains('register<VpNoTestCaCheck>'));
    expect(gradle, contains('finalizedBy(check)'));
  });

  test('no CA certificate or key is committed', () {
    final tracked = Process.runSync('git', ['ls-files']).stdout as String;
    final files = tracked
        .split('\n')
        .where((p) => RegExp(r'\.(pem|crt|cer|der|key)$').hasMatch(p.trim()));
    expect(files, isEmpty);
  });
}
