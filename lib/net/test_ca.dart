import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// G8: a debug build may trust one extra CA, the test stack's, so it can
/// sign in and register there. Release and profile builds never do (spec 22,
/// S1): the define is read only when [kDebugMode] is true, so in those builds
/// the constant is empty and the certificate never reaches the snapshot.
///
/// Give it at build time as base64 of the CA's PEM file (the certificate
/// only, never its key), for example
/// `flutter run --dart-define=VP_TEST_CA_B64=$(base64 -w0 test-stack-ca.pem)`.
/// The same define makes the Android debug build trust it for native HTTPS
/// (`android/app/build.gradle.kts`) and liblinphone for SIP TLS
/// (`TestCaTrust.kt`). The certificate is never committed.
const testCaDefine = 'VP_TEST_CA_B64';

const _testCaB64 = kDebugMode ? String.fromEnvironment(testCaDefine) : '';

/// The test stack's CA in PEM, or null (every release and profile build, and
/// a debug build without the define).
final String? testStackCaPem = parseTestCa(_testCaB64, debugBuild: kDebugMode);

/// The PEM in [b64], or null when [debugBuild] is false or [b64] is empty.
/// Throws [ArgumentError] when it isn't base64 of a PEM certificate, or when
/// it holds a private key.
String? parseTestCa(String b64, {required bool debugBuild}) {
  if (!debugBuild) return null;
  final trimmed = b64.trim();
  if (trimmed.isEmpty) return null;
  final String pem;
  try {
    pem = utf8.decode(base64.decode(trimmed));
  } on FormatException {
    throw ArgumentError('$testCaDefine is not base64 of a PEM file');
  }
  if (pem.contains('PRIVATE KEY')) {
    throw ArgumentError(
      '$testCaDefine holds a private key; give the CA certificate only',
    );
  }
  if (!pem.contains('-----BEGIN CERTIFICATE-----')) {
    throw ArgumentError('$testCaDefine holds no PEM certificate');
  }
  return pem;
}

/// The system's roots plus [pem], for the API's HttpClient.
SecurityContext testCaContext(String pem) =>
    SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(utf8.encode(pem));
