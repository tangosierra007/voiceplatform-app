/// Text cases shared with vp_linphone's `LogScrubber` (packages/vp_linphone,
/// app PR #5): both scrubbers must give exactly these outputs. Keep this table
/// identical in both test suites. ACMA fictional numbers only.
const sharedScrubCases = <(String, String)>[
  (
    'Authorization: Digest username="app-abcde12345", realm="democo.sip.voiceplatform.com.au", '
        'nonce="5f2c1a", uri="sip:democo.sip.voiceplatform.com.au", response="6629fae49393a05397450978507c4ef1"',
    'Authorization: [scrubbed]',
  ),
  (
    'Proxy-Authorization: Digest username="app-abcde12345", response="0a4f113eab"\r\nMax-Forwards: 70\r\n',
    'Proxy-Authorization: [scrubbed]\r\nMax-Forwards: 70\r\n',
  ),
  (
    'Authentication-Info: nextnonce="47364c23432d2e", qop=auth, rspauth="6629fae4", cnonce="0a4f"',
    'Authentication-Info: nextnonce=[scrubbed], qop=auth, rspauth=[scrubbed], cnonce=[scrubbed]',
  ),
  ('password=hunter2hunter next', 'password=[scrubbed] next'),
  ('passwd: "q w e"', 'passwd: [scrubbed]'),
  ('ha1 = 5ebe2294ecd0e0f08eab7690d2a6ee69;', 'ha1 = [scrubbed];'),
  ('pass=hunter2hunter&u=1', 'pass=[scrubbed]&u=1'),
  (
    '{"password":"hunter2hunter","user":"ava"}',
    '{"password":[scrubbed],"user":"ava"}',
  ),
  ('{"token": "abc.def"}', '{"token": [scrubbed]}'),
  ('{password: hunter2hunter}', '{password: [scrubbed]}'),
  ('{"access_token":abcdef}', '{"access_token":[scrubbed]}'),
  (
    'Contact: <sip:app-x@192.0.2.10;transport=tls;pn-provider=fcm;pn-prid=dXk3:APA91bH-x_y;pn-param=voiceplatform-app>',
    'Contact: <sip:app-x@192.0.2.10;transport=tls;pn-provider=fcm;pn-prid=[scrubbed];pn-param=voiceplatform-app>',
  ),
  (
    'Authorisation Bearer abc.def-ghi_jkl ok',
    'Authorisation Bearer [scrubbed] ok',
  ),
  (
    'From: <sip:+61491570737@democo.sip.voiceplatform.com.au>',
    'From: <sip:[n]@democo.sip.voiceplatform.com.au>',
  ),
  ('dial 0491 570 737 now', 'dial [n] now'),
  ('dial 0491-570-737 now', 'dial [n] now'),
  ('dial (03) 5550 1201 now', 'dial ([n] now'),
  ('dial 0491.570.737 now', 'dial [n] now'),
  ('dial 03/5550/1201 now', 'dial [n] now'),
  ('dial +61.3.5550.1201 now', 'dial [n] now'),
  (
    'ext 204 port 5061 ip 192.0.2.20 code 486',
    'ext 204 port 5061 ip 192.0.2.20 code 486',
  ),
  ('via 192.0.2.20:5061', 'via 192.0.2.20:5061'),
  ('user ava.nguyen@example.com signed in', 'user [email] signed in'),
  (
    '<sip:app-abc@democo.sip.voiceplatform.com.au>',
    '<sip:app-abc@democo.sip.voiceplatform.com.au>',
  ),
  (
    '2026 Oct 27 03:15:00.123Z ENGINE call call-1 CONNECTED',
    '2026 Oct 27 03:15:00.123Z ENGINE call call-1 CONNECTED',
  ),
];
