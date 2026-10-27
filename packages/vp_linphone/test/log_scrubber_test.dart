import 'package:flutter_test/flutter_test.dart';
import 'package:vp_linphone/vp_linphone.dart';

// The same sample lines as the Kotlin sink's LogScrubberTest.
// ACMA fictional numbers only.
void main() {
  const password = 'testpasswordtestpassword';
  final s = LogScrubber(secrets: [password]);
  final sixDigits = RegExp(r'\d{6,}');

  test('Authorization header value', () {
    const line =
        'Authorization: Digest username="app-abcde12345", realm="democo.sip.voiceplatform.com.au", '
        'nonce="5f2c1a", uri="sip:democo.sip.voiceplatform.com.au", response="6629fae49393a05397450978507c4ef1"';
    expect(s.scrub(line), 'Authorization: [scrubbed]');
  });

  test('Proxy-Authorization inside a multi-line SIP message', () {
    const msg =
        'INVITE sip:204@democo.sip.voiceplatform.com.au SIP/2.0\r\n'
        'Proxy-Authorization: Digest username="app-abcde12345", response="0a4f113eab"\r\n'
        'Max-Forwards: 70\r\n';
    final out = s.scrub(msg);
    expect(out, isNot(contains('0a4f113eab')));
    expect(out, contains('Proxy-Authorization: [scrubbed]\r\n'));
    expect(out, contains('Max-Forwards: 70'));
  });

  test('the known password anywhere', () {
    final out = s.scrub('auth info for app-abcde12345 with $password set');
    expect(out, isNot(contains(password)));
    expect(out, contains('[scrubbed]'));
  });

  test('password-like pairs', () {
    final plain = LogScrubber();
    expect(plain.scrub('password=hunter2hunter next'), 'password=[scrubbed] next');
    expect(plain.scrub('passwd: "q w e"'), 'passwd: [scrubbed]');
    expect(plain.scrub('ha1 = 5ebe2294ecd0e0f08eab7690d2a6ee69;'), 'ha1 = [scrubbed];');
  });

  test('push token and bearer token', () {
    final out = s.scrub(
      'Contact: <sip:app-x@192.0.2.10;transport=tls;pn-provider=fcm;pn-prid=dXk3:APA91bH-x_y;pn-param=voiceplatform-app>',
    );
    expect(out, isNot(contains('APA91')));
    expect(out, contains('pn-prid=[scrubbed]'));
    expect(out, contains('pn-param=voiceplatform-app'));
    expect(s.scrub('Authorisation Bearer abc.def-ghi_jkl ok'), 'Authorisation Bearer [scrubbed] ok');
  });

  test('full phone numbers', () {
    expect(
      s.scrub('From: <sip:+61491570737@democo.sip.voiceplatform.com.au>'),
      'From: <sip:[n]@democo.sip.voiceplatform.com.au>',
    );
    expect(s.scrub('dial 0491 570 737 now'), 'dial [n] now');
    expect(s.scrub('dial 0491-570-737 now'), 'dial [n] now');
    expect(s.scrub('dial (03) 5550 1201 now'), 'dial ([n] now');
    expect(sixDigits.hasMatch(s.scrub('a 0355501201 b 61355501201')), isFalse);
  });

  test('short numbers, ports and addresses survive', () {
    const line = 'ext 204 port 5061 ip 192.0.2.20 code 486';
    expect(s.scrub(line), line);
  });

  test('emails go, SIP URIs stay', () {
    expect(s.scrub('user ava.nguyen@example.com signed in'), 'user [email] signed in');
    const uri = '<sip:app-abc@democo.sip.voiceplatform.com.au>';
    expect(s.scrub(uri), uri);
  });

  test('log timestamps survive a second scrub', () {
    const line = '2026 Oct 27 03:15:00.123Z ENGINE call call-1 CONNECTED';
    expect(s.scrub(line), line);
  });

  test('Authentication-Info parameters', () {
    expect(
      s.scrub('Authentication-Info: nextnonce="47364c23432d2e", qop=auth, rspauth="6629fae4", cnonce="0a4f"'),
      'Authentication-Info: nextnonce=[scrubbed], qop=auth, rspauth=[scrubbed], cnonce=[scrubbed]',
    );
  });

  test('JSON-style keys and pass=', () {
    final plain = LogScrubber();
    expect(plain.scrub('{"password":"hunter2hunter","user":"ava"}'), '{"password":[scrubbed],"user":"ava"}');
    expect(plain.scrub('{"token": "abc.def"}'), '{"token": [scrubbed]}');
    expect(plain.scrub('{password: hunter2hunter}'), '{password: [scrubbed]}');
    expect(plain.scrub('{"access_token":abcdef}'), '{"access_token":[scrubbed]}');
    expect(plain.scrub('pass=hunter2hunter&u=1'), 'pass=[scrubbed]&u=1');
  });

  test('numbers with dots and slashes; IPv4 kept', () {
    expect(s.scrub('dial 0491.570.737 now'), 'dial [n] now');
    expect(s.scrub('dial 03/5550/1201 now'), 'dial [n] now');
    expect(s.scrub('dial +61.3.5550.1201 now'), 'dial [n] now');
    expect(s.scrub('via 192.0.2.20:5061'), 'via 192.0.2.20:5061');
  });

  test('idempotent', () {
    final once = s.scrub('Authorization: Digest response="x" from 0491 570 737 $password');
    expect(s.scrub(once), once);
  });
}
