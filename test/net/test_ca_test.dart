import 'dart:convert';
import 'dart:io';

import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/net/api.dart';
import 'package:voiceplatform_app/net/test_ca.dart';

// G8: only a debug build may trust the test stack's CA (spec 22, S1).
//
// A self-signed certificate made for this test only. Its private key was
// deleted when it was made, so nothing can be signed with it and it is
// trusted nowhere; it is not the test stack's CA, which is never committed.
const _fixtureCa = '''
-----BEGIN CERTIFICATE-----
MIIB+zCCAaGgAwIBAgIULbCVjfifrwXWE5l02inID9jPS3MwCgYIKoZIzj0EAwIw
UjEgMB4GA1UECgwXVm9pY2VQbGF0Zm9ybSBhcHAgdGVzdHMxLjAsBgNVBAMMJVRl
c3QgZml4dHVyZSBDQSwgbm90IHRydXN0ZWQgYW55d2hlcmUwIBcNMjYxMTIyMTQz
NzAyWhgPMjEyNjEwMjkxNDM3MDJaMFIxIDAeBgNVBAoMF1ZvaWNlUGxhdGZvcm0g
YXBwIHRlc3RzMS4wLAYDVQQDDCVUZXN0IGZpeHR1cmUgQ0EsIG5vdCB0cnVzdGVk
IGFueXdoZXJlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE1s67t8TkHsKcb7du
3A83JPKSWXW9ZCB+1o4ayyOJH4j0iQzRhKCF1IfHmwRpOxWA7Ge1ojCm9FNozJaC
rskQlqNTMFEwHQYDVR0OBBYEFGPlB0QekLFyWURTnrDkbSBhfoNFMB8GA1UdIwQY
MBaAFGPlB0QekLFyWURTnrDkbSBhfoNFMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZI
zj0EAwIDSAAwRQIhAMBgZm4ZcagNpbPq9cTmJQgTRllAJaqrkokNZ0gMsIEMAiBW
Rrcd0GbNhvcZmXETY6ojJMuOx953u5V1VcZgA1RLCw==
-----END CERTIFICATE-----
''';

String _b64(String s) => base64.encode(utf8.encode(s));

const _config = ApiConfig(
  baseUrl: 'https://api.example.com/app/v1',
  platform: 'android',
  appVersion: '1.0.0',
);

void main() {
  group('parseTestCa', () {
    test('a debug build with the define trusts the extra CA', () {
      expect(parseTestCa(_b64(_fixtureCa), debugBuild: true), _fixtureCa);
    });

    test('a release build ignores the define', () {
      expect(parseTestCa(_b64(_fixtureCa), debugBuild: false), isNull);
    });

    test('no define, no extra CA', () {
      expect(parseTestCa('', debugBuild: true), isNull);
      expect(parseTestCa('  ', debugBuild: true), isNull);
    });

    test('a private key is refused', () {
      // Split so no secret scanner reads it as a key; it is only a marker.
      const key =
          '-----BEGIN PRIVATE'
          ' KEY-----\nX\n';
      expect(
        () => parseTestCa(_b64(_fixtureCa + key), debugBuild: true),
        throwsArgumentError,
      );
    });

    test('anything but base64 of a PEM certificate is refused', () {
      expect(
        () => parseTestCa('not base64!', debugBuild: true),
        throwsArgumentError,
      );
      expect(
        () => parseTestCa(_b64('hello'), debugBuild: true),
        throwsArgumentError,
      );
    });

    test('these tests run as a debug build without the define', () {
      // flutter test is a debug build; CI passes no VP_TEST_CA_B64.
      expect(testStackCaPem, isNull);
    });
  });

  group('the API client', () {
    test('trusts the extra CA beside the system roots when given one', () {
      final dio = buildDio(
        _config,
        accessToken: () => null,
        trustedCaPem: _fixtureCa,
      );
      final adapter = dio.httpClientAdapter;
      expect(adapter, isA<IOHttpClientAdapter>());
      final create = (adapter as IOHttpClientAdapter).createHttpClient;
      expect(create, isNotNull);
      // The certificate parses into the client's trust store.
      final client = create!();
      addTearDown(client.close);
      expect(client, isA<HttpClient>());
    });

    test('keeps the default client without one', () {
      final dio = buildDio(_config, accessToken: () => null);
      final adapter = dio.httpClientAdapter;
      expect(
        adapter is IOHttpClientAdapter && adapter.createHttpClient != null,
        isFalse,
      );
    });

    test('a broken certificate fails loudly, not silently untrusted', () {
      const broken =
          '-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n';
      expect(() => testCaContext(broken), throwsA(isA<TlsException>()));
    });
  });
}
