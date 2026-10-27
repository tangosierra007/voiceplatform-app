import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voiceplatform_app/diagnostics/scrubber.dart';

import 'diagnostics/shared_scrub_cases.dart';

// APP9 and APP12: what the on-device scrubber removes before anything reaches
// GlitchTip. ACMA fictional numbers and example.com addresses only.
void main() {
  final sixDigits = RegExp(r'\d{6,}');

  group('shared with vp_linphone LogScrubber', () {
    final s = DiagnosticsScrubber();
    for (final (input, expected) in sharedScrubCases) {
      test(input.split('\n').first, () {
        expect(s.scrub(input), expected);
        expect(s.scrub(expected), expected, reason: 'idempotent');
      });
    }
  });

  group('text rules', () {
    late DiagnosticsScrubber s;
    setUp(() => s = DiagnosticsScrubber());

    test('a SIP password registered at run time, anywhere', () {
      const password = 'testpasswordtestpassword';
      s.addSecret(password);
      final out = s.scrub('register app-abcde12345 pw $password, again:$password');
      expect(out, isNot(contains(password)));
      expect(out, contains(DiagnosticsScrubber.redacted));
    });

    test('digest Authorization and Proxy-Authorization, nonces and responses', () {
      final out = s.scrub(
        'SIP/2.0 401\r\nWWW-Authenticate: Digest realm="r", nonce="abc123", opaque="op1"\r\n'
        'Authorization: Digest username="u", response="ffee"\r\n'
        'Proxy-Authorization: Digest username="u", nc=00000001, cnonce="c1"\r\n',
      );
      for (final v in ['abc123', 'op1', 'ffee', 'c1', '00000001']) {
        expect(out, isNot(contains(v)), reason: v);
      }
      expect(out, contains('Authorization: [scrubbed]\r\n'));
      expect(out, contains('Proxy-Authorization: [scrubbed]\r\n'));
    });

    test('bearer, access and refresh tokens', () {
      expect(s.scrub('Authorization: Bearer vp_at_1a2b3c'), 'Authorization: [scrubbed]');
      expect(s.scrub('header Bearer vp_at_1a2b3c sent'), 'header Bearer [scrubbed] sent');
      expect(s.scrub('{"accessToken":"at-1","refreshToken":"rt-2"}'), '{"accessToken":[scrubbed],"refreshToken":[scrubbed]}');
      expect(s.scrub('refresh_token=rt-2&x=1'), 'refresh_token=[scrubbed]&x=1');
      expect(s.scrub('refusalToken: rf-3'), 'refusalToken: [scrubbed]');
    });

    test('request secrets, keyed or bare', () {
      // A fake 32-byte base64url value, built at run time for the secret scan.
      final secret = List.generate(43, (i) => 'q0wE-rT_y9'[i % 10]).join();
      expect(s.scrub('{"requestSecret":"$secret"}'), '{"requestSecret":[scrubbed]}');
      expect(s.scrub('request_secret=$secret'), 'request_secret=[scrubbed]');
      expect(s.scrub('complete with $secret failed'), 'complete with [scrubbed] failed');
    });

    test('6-digit sign-in codes', () {
      expect(s.scrub('code 482913 rejected'), 'code [n] rejected');
      expect(s.scrub('{"code":"482913"}'), '{"code":"[n]"}');
      expect(sixDigits.hasMatch(s.scrub('482 913 and 48-29-13')), isFalse);
    });

    test('App Link, QR and media tokens', () {
      expect(
        s.scrub('open https://portal.example.com/app/signin/req_8f2/Lk-9aZ_tok?x=1'),
        'open https://portal.example.com/app/signin/[scrubbed]?x=1',
      );
      expect(s.scrub('scanned vpapp://signin/QrT0k3n_abc'), 'scanned vpapp://signin/[scrubbed]');
      expect(s.scrub('GET /app/v1/media/mt_77aa?code=9f'), 'GET /app/v1/media/[scrubbed]?code=[scrubbed]');
      expect(s.scrub('https://bucket.example.com/vm.ogg?X-Amz-Signature=abcd&ok=1'), 'https://bucket.example.com/vm.ogg?X-Amz-Signature=[scrubbed]&ok=1');
    });

    test('email addresses go, SIP URIs stay', () {
      expect(s.scrub('Ava <ava.nguyen+app@example.com>'), 'Ava <[email]>');
      expect(s.scrub('sip:204@democo.sip.voiceplatform.com.au'), 'sip:204@democo.sip.voiceplatform.com.au');
    });

    test('phone numbers: any 6+ digit run, with separators', () {
      for (final n in ['0491570737', '+61 491 570 737', '(03) 9555 0123', '1800 160 401', '+61-3-9555-0123', '491570']) {
        final out = s.scrub('call $n now');
        expect(sixDigits.hasMatch(out.replaceAll(RegExp(r'\D'), '')), isFalse, reason: n);
      }
      expect(s.scrub('ext 204, 12345 left'), 'ext 204, 12345 left');
    });

    test('JSON-style password and token keys', () {
      expect(s.scrub('{"password": "p w"}'), '{"password": [scrubbed]}');
      expect(s.scrub('{"sipPassword":"x1"}'), '{"sipPassword":[scrubbed]}');
      expect(s.scrub('{"token":"t1","linkToken":"t2"}'), '{"token":[scrubbed],"linkToken":[scrubbed]}');
    });

    test('address-book values registered in memory become [contact]', () {
      s.rememberAddressBookValues(['Mia Thompson', 'Plumber Joe']);
      expect(s.scrub('ringing from mia thompson (Plumber Joe)'), 'ringing from [contact] ([contact])');
      s.forgetAddressBookValues();
      expect(s.scrub('Mia Thompson'), 'Mia Thompson');
    });
  });

  group('structured data', () {
    final s = DiagnosticsScrubber();

    test('secret-named keys lose their values', () {
      final out = s.scrubJson({
        'headers': {'Authorization': 'Digest x', 'Cookie': 'a=b', 'Accept': 'json'},
        'otp': '123456',
        'code': 'update_required',
        'pin': 4321,
        'nested': [
          {'access_token': 'abc'},
        ],
      });
      expect(out, {
        'headers': {'Authorization': '[scrubbed]', 'Cookie': '[scrubbed]', 'Accept': 'json'},
        'otp': '[scrubbed]',
        'code': 'update_required',
        'pin': '[scrubbed]',
        'nested': [
          {'access_token': '[scrubbed]'},
        ],
      });
    });

    test('event: no user, no server name, no cookies; SDK fields kept; device name removed', () {
      final out = s.scrubEventJson({
        'event_id': '0123456789abcdef0123456789abcdef',
        'timestamp': '2026-10-28T01:02:03.000Z',
        'release': 'voiceplatform-app@1.0.0+123',
        'server_name': 'tjs-phone',
        'user': {'email': 'ava@example.com', 'ip_address': '{{auto}}'},
        'message': {'formatted': 'failed for ava@example.com on 0491 570 737'},
        'exception': {
          'values': [
            {
              'type': 'StateError',
              'value': 'password=hunter2hunter',
              'stacktrace': {
                'frames': [
                  {'filename': 'scrubber.dart', 'lineno': 10},
                ],
              },
            },
          ],
        },
        'contexts': {
          'device': {'name': "Ava's Pixel", 'model': 'Pixel 8'},
          'os': {'name': 'Android', 'version': '15'},
          'call': {'remote': '+61 491 570 737'},
        },
        'request': {
          'url': 'https://api.example.com/app/v1/media/mt_77aa',
          'cookies': 'sid=1',
          'headers': {'Authorization': 'Bearer x'},
        },
      });
      expect(out.containsKey('user'), isFalse);
      expect(out.containsKey('server_name'), isFalse);
      expect(out['event_id'], '0123456789abcdef0123456789abcdef');
      expect(out['timestamp'], '2026-10-28T01:02:03.000Z');
      expect(out['release'], 'voiceplatform-app@1.0.0+123');
      expect((out['message'] as Map)['formatted'], 'failed for [email] on [n]');
      final ex = ((out['exception'] as Map)['values'] as List).single as Map;
      expect(ex['value'], 'password=[scrubbed]');
      expect(ex['stacktrace'], isNotNull);
      final contexts = out['contexts'] as Map;
      expect(contexts['device'], {'model': 'Pixel 8'});
      expect(contexts['os'], {'name': 'Android', 'version': '15'});
      expect(contexts['call'], {'remote': '[n]'});
      expect(out['request'], {
        'url': 'https://api.example.com/app/v1/media/[scrubbed]',
        'headers': {'Authorization': '[scrubbed]'},
      });
    });

    test('APP12: address-book data is dropped entirely', () {
      final out = s.scrubEventJson({
        'extra': {
          'contacts': [
            {'name': 'Mia Thompson', 'phone': '0491 570 737'},
          ],
          'addressBook': 'x',
          'kept': 'yes',
        },
        'tags': {'contact_count': '12', 'tab': 'keypad'},
        'contexts': {
          'phone_book': {'size': 3},
        },
        'breadcrumbs': [
          {'category': 'contacts', 'message': 'loaded Mia Thompson'},
          {'category': 'ui', 'type': 'address_book', 'message': 'opened'},
          {'category': 'nav', 'message': 'to keypad', 'data': {'contact': 'Mia Thompson', 'tab': 'keypad'}},
        ],
      });
      final text = jsonEncode(out);
      expect(text, isNot(contains('Mia')));
      expect(text, isNot(contains('0491')));
      expect(out['extra'], {'kept': 'yes'});
      expect(out['tags'], {'tab': 'keypad'});
      expect(out['contexts'], isEmpty);
      expect(out['breadcrumbs'], [
        {
          'category': 'nav',
          'message': 'to keypad',
          'data': {'tab': 'keypad'},
        },
      ]);
    });

    test('APP12: an address-book breadcrumb is dropped', () {
      expect(s.scrubBreadcrumbJson({'category': 'contacts.load', 'message': 'ok'}), isNull);
      expect(s.scrubBreadcrumbJson({'category': 'http', 'data': {'url': 'https://x.example.com/?code=1'}}), {
        'category': 'http',
        'data': {'url': 'https://x.example.com/?code=[scrubbed]'},
      });
    });

    test('attachments: text scrubbed, binary and address-book files dropped', () {
      final out = s.scrubAttachment(
        filename: 'call.log',
        contentType: 'text/plain',
        bytes: utf8.encode('password=hunter2hunter to 0491 570 737'),
      );
      expect(utf8.decode(out!), 'password=[scrubbed] to [n]');
      expect(s.scrubAttachment(filename: 'screen.png', contentType: 'image/png', bytes: [1, 2, 3]), isNull);
      expect(s.scrubAttachment(filename: 'logs.gz', contentType: 'application/gzip', bytes: [1]), isNull);
      expect(s.scrubAttachment(filename: 'contacts.json', contentType: 'application/json', bytes: utf8.encode('{}')), isNull);
    });
  });
}
