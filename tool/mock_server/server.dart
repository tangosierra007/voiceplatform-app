// A mock of the app API (contracts/app-api.openapi.yaml) for the app's
// screens, widget tests and manual runs. dart:io only, no packages.
//
//   dart run tool/mock_server/main.dart [--port 3000] [--presence-every 5]
//
// Serves every route in the contract under /app/v1 with the canvas sample
// data in fixtures.dart, keeps small in-memory state (status, office hours,
// read flags, sent texts), and streams /events with a presence.snapshot, a
// badges event and then a scripted presence change every few seconds.
//
// Like the real API it wants `X-VP-App` on every request, a bearer token on
// authenticated routes (any non-empty value), and answers 426 below the
// minimum version. Mock-only sign-in values are in SignInFixtures.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'fixtures.dart';

typedef _Handler = Future<void> Function(_Req r);

class MockServer {
  MockServer._(
    this._server,
    this.presenceEvery,
    this.heartbeatEvery,
    this.minimumVersion,
    this.recommendedVersion,
    this.now,
    this.resendAfter,
    this.accessLifetime,
  );

  final HttpServer _server;
  final Duration presenceEvery;
  final Duration heartbeatEvery;
  final String minimumVersion;
  final String recommendedVersion;

  /// The mock's clock, for code expiry, resend waits and token lifetimes.
  final DateTime Function() now;
  final Duration resendAfter;
  final Duration accessLifetime;

  static const basePath = '/app/v1';

  Uri get baseUri =>
      Uri.parse('http://${_server.address.address}:${_server.port}$basePath');
  int get port => _server.port;

  // ----- state
  String _status = 'available';
  String _officeMode = 'schedule';
  final Map<String, bool> _deviceRings = {};
  final Set<String> _heardChanged = {};
  final Set<String> _deletedVoicemail = {};
  final Set<String> _readThreads = {};
  final List<Map<String, Object?>> _sent = [];
  final Map<String, _SignInRequest> _requests = {};
  final Map<String, DateTime> _accessTokens = {};
  final Map<String, _RefreshState> _refreshTokens = {};
  final Map<String, DateTime> _refusalTokens = {};
  final Set<String> _usedQr = {};
  final Map<String, String> _presence = {
    for (final c in colleagues) '${c['n']}': c['presence'] as String,
  };
  final Map<String, DateTime> _presenceSince = {};
  final List<StreamController<String>> _streams = [];
  final _rand = Random.secure();
  int _scriptStep = 0;
  Timer? _scriptTimer;

  static Future<MockServer> start({
    int port = 3000,
    InternetAddress? address,
    Duration presenceEvery = const Duration(seconds: 5),
    Duration heartbeatEvery = const Duration(seconds: 25),
    String minimumVersion = '1.0.0',
    String? recommendedVersion,
    DateTime Function()? now,
    Duration resendAfter = const Duration(seconds: 60),
    Duration accessLifetime = const Duration(minutes: 15),
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final mock = MockServer._(
      server,
      presenceEvery,
      heartbeatEvery,
      minimumVersion,
      recommendedVersion ?? minimumVersion,
      now ?? DateTime.now,
      resendAfter,
      accessLifetime,
    );
    final started = mock.now().toUtc();
    for (final c in colleagues) {
      if (c['ago'] != null) {
        mock._presenceSince['${c['n']}'] = started.subtract(
          Duration(seconds: c['ago'] as int),
        );
      }
    }
    server.listen(mock._handle);
    return mock;
  }

  Future<void> close() async {
    _scriptTimer?.cancel();
    for (final s in _streams.toList()) {
      await s.close();
    }
    await _server.close(force: true);
  }

  // ------------------------------------------------------------- routing

  late final List<(String, RegExp, bool, _Handler)> _routes = [
    // (method, path, authenticated, handler)
    ('GET', _p('/config'), false, _config),
    ('POST', _p('/auth/email-requests'), false, _emailRequest),
    ('POST', _p('/auth/email-requests/{id}/resend'), false, _resend),
    ('POST', _p('/auth/email-requests/{id}/complete'), false, _complete),
    ('POST', _p('/auth/qr/complete'), false, _qrComplete),
    ('POST', _p('/auth/refresh'), false, _refresh),
    ('POST', _p('/auth/licence-requests'), false, _licenceRequest),
    ('GET', _p('/me'), true, (r) => r.json(200, me(status: _status))),
    ('PUT', _p('/me/status'), true, _putStatus),
    ('GET', _p('/me/call-settings'), true, (r) => r.json(200, callSettings)),
    ('PATCH', _p('/me/call-settings'), true, _patchCallSettings),
    ('GET', _p('/me/caller-ids'), true, (r) => r.json(200, callerIds)),
    (
      'GET',
      _p('/me/office-hours'),
      true,
      (r) => r.json(200, [officeHours(_officeMode)]),
    ),
    ('POST', _p('/me/office-hours/{id}/override'), true, _override),
    ('GET', _p('/me/devices'), true, _devices),
    ('PATCH', _p('/me/devices/{id}'), true, _patchDevice),
    ('POST', _p('/me/devices/{id}/sign-out'), true, _signOutDevice),
    ('POST', _p('/devices/me/sip-credentials'), true, _sipCredentials),
    ('PUT', _p('/devices/me/push-token'), true, (r) => r.empty(204)),
    ('POST', _p('/devices/me/sign-out'), true, (r) => r.empty(204)),
    (
      'POST',
      _p('/calls/via-desk-phone'),
      true,
      (r) => r.json(202, {'deskPhone': 'Desk phone 202'}),
    ),
    ('GET', _p('/directory/colleagues'), true, _colleagues),
    ('GET', _p('/directory/teams'), true, (r) => r.json(200, teams)),
    ('GET', _p('/directory/shared-contacts'), true, _sharedContacts),
    ('GET', _p('/events'), true, _events),
    ('GET', _p('/presence'), true, _presenceRoute),
    ('GET', _p('/history'), true, _history),
    ('POST', _p('/history/seen'), true, (r) => r.empty(204)),
    ('GET', _p('/voicemail/boxes'), true, (r) => r.json(200, voicemailBoxes)),
    ('GET', _p('/voicemail/messages'), true, _voicemails),
    ('POST', _p('/voicemail/messages/{id}/media-url'), true, _voicemailMedia),
    ('POST', _p('/voicemail/messages/{id}/read'), true, _voicemailRead),
    ('POST', _p('/voicemail/messages/{id}/delete'), true, _voicemailDelete),
    ('GET', _p('/voicemail/greetings'), true, (r) => r.json(200, greetings)),
    ('PUT', _p('/voicemail/greetings/{kind}'), true, _putGreeting),
    ('DELETE', _p('/voicemail/greetings/{kind}'), true, (r) => r.empty(204)),
    (
      'POST',
      _p('/voicemail/greetings/{kind}/media-url'),
      true,
      (r) => r.json(200, _mediaUrl('greeting-${r.params[0]}')),
    ),
    ('POST', _p('/voicemail/pin'), true, _pin),
    ('GET', _p('/recordings'), true, (r) => _page(r, recordings)),
    ('POST', _p('/recordings/{id}/media-url'), true, _recordingMedia),
    ('GET', _p('/media/{token}'), true, _media),
    ('GET', _p('/messages/lines'), true, (r) => r.json(200, smsLines)),
    ('GET', _p('/messages/threads'), true, _threads),
    ('GET', _p('/messages/threads/{id}/messages'), true, _threadMessages),
    ('POST', _p('/messages/threads/{id}/read'), true, _readThread),
    ('POST', _p('/messages/send'), true, _send),
    (
      'POST',
      _p('/diagnostics/call-logs'),
      true,
      (r) => r.json(201, {'reference': 'LOG-7F3K9Q'}),
    ),
  ];

  static RegExp _p(String path) => RegExp(
    '^$basePath${path.replaceAll(RegExp(r'\{[a-zA-Z]+\}'), '([^/]+)')}\$',
  );

  Future<void> _handle(HttpRequest req) async {
    final r = _Req(req);
    try {
      final path = req.uri.path;
      final matches = [
        for (final route in _routes)
          if (route.$2.hasMatch(path)) route,
      ];
      if (matches.isEmpty) {
        return await r.error(404, 'not_found', 'No route $path');
      }
      final route = matches.where((m) => m.$1 == req.method).firstOrNull;
      if (route == null) {
        return await r.error(405, 'method_not_allowed', '${req.method} $path');
      }
      r.params = route.$2
          .firstMatch(path)!
          .groups(
            List.generate(route.$2.firstMatch(path)!.groupCount, (i) => i + 1),
          )
          .cast<String>();

      final app = req.headers.value('x-vp-app');
      final version = _appVersion(app);
      if (version == null) {
        return await r.error(
          400,
          'validation',
          'X-VP-App: <platform>/<version> is required',
        );
      }
      final authed = route.$3 || path.endsWith('/auth/refresh');
      if (authed && _older(version, minimumVersion)) {
        return await r.json(426, _appConfig(app!.split('/').first));
      }
      if (route.$3) {
        final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
        if (!auth.startsWith('Bearer ') || auth.length <= 7) {
          return await r.error(401, 'unauthorized', 'Bearer token required');
        }
        // Tokens this mock issued expire; any other non-empty bearer is
        // accepted, for hand testing with curl.
        final expires = _accessTokens[auth.substring(7)];
        if (expires != null && !now().isBefore(expires)) {
          return await r.error(401, 'token_expired', 'Access token expired');
        }
      }
      // Like the API's zod schemas: an optional field may be left out but
      // never sent as null (only CallSettingsPatch's clearable fields are
      // nullable in the contract).
      final json = req.headers.contentType?.mimeType == 'application/json';
      if (json && !path.endsWith('/me/call-settings')) {
        final raw = utf8.decode(await r.bytes());
        if (raw.isNotEmpty) {
          final where = _nullAt(jsonDecode(raw), '');
          if (where != null) {
            return await r.error(
              400,
              'validation',
              '$where: Expected string, received null',
            );
          }
        }
      }
      await route.$4(r);
    } catch (e) {
      if (!r.done) await r.error(500, 'mock_error', '$e');
    }
  }

  /// The path of the first null in [v], or null when there is none.
  static String? _nullAt(Object? v, String at) {
    if (v == null) return at.isEmpty ? '(body)' : at;
    if (v is Map) {
      for (final e in v.entries) {
        final hit = _nullAt(e.value, at.isEmpty ? '${e.key}' : '$at.${e.key}');
        if (hit != null) return hit;
      }
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        final hit = _nullAt(v[i], '$at[$i]');
        if (hit != null) return hit;
      }
    }
    return null;
  }

  static String? _appVersion(String? header) {
    if (header == null) return null;
    final m = RegExp(r'^(android|ios|windows|macos)/(\d+\.\d+\.\d+)')
        .firstMatch(header);
    return m?.group(2);
  }

  static bool _older(String a, String b) {
    final x = a.split('.').map(int.parse).toList();
    final y = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] < y[i];
    }
    return false;
  }

  Map<String, Object?> _appConfig(String platform) => {
    'platform': platform,
    'minimumVersion': minimumVersion,
    'recommendedVersion': recommendedVersion,
    'storeUrl': 'https://play.google.com/store/apps/details?id=au.com.voiceplatform.app',
  };

  // ------------------------------------------------------------ sign-in

  Future<void> _config(_Req r) {
    final platform = r.query['platform'];
    if (!const ['android', 'ios', 'windows', 'macos'].contains(platform)) {
      return r.error(400, 'validation', 'platform is required');
    }
    return r.json(200, _appConfig(platform!));
  }

  String _token() => base64Url
      .encode(List.generate(32, (_) => _rand.nextInt(256)))
      .replaceAll('=', '');

  String _uuid() {
    final b = List.generate(16, (_) => _rand.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Map<String, Object?> _accepted(String id) => {
    'requestId': id,
    'expiresInSeconds': 600,
    'resendAfterSeconds': resendAfter.inSeconds,
  };

  /// The same 202 for any well-formed email: known, unknown, Basic (APP2).
  Future<void> _emailRequest(_Req r) async {
    final body = await r.body();
    final email = body['email'];
    if (email is! String ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        body['requestSecret'] is! String ||
        body['device'] is! Map) {
      return r.error(
        400,
        'validation',
        'email, requestSecret and device are required',
      );
    }
    final id = _uuid();
    _requests[id] = _SignInRequest(
      email.toLowerCase(),
      body['requestSecret'] as String,
      now(),
    );
    return r.json(202, _accepted(id));
  }

  Future<void> _resend(_Req r) async {
    final body = await r.body();
    final req = _requests[r.params[0]];
    if (req != null && req.secret == body['requestSecret']) {
      final wait = req.sentAt.add(resendAfter).difference(now());
      if (wait > Duration.zero) {
        r.req.response.headers.set('Retry-After', '${wait.inSeconds + 1}');
        return r.error(
          429,
          'rate_limited',
          'Wait a moment before sending again.',
        );
      }
      // A new code replaces the old one; the link stays the same request.
      req
        ..attempts = 0
        ..sentAt = now()
        ..createdAt = now();
    }
    return r.json(202, _accepted(r.params[0]));
  }

  Map<String, Object?> _session(String email) {
    final at = now().toUtc();
    final access = _token();
    final refresh = _token();
    _accessTokens[access] = at.add(accessLifetime);
    _refreshTokens[refresh] = _RefreshState(email);
    return {
      'accessToken': access,
      'accessExpiresAt': at.add(accessLifetime).toIso8601String(),
      'refreshToken': refresh,
      'refreshExpiresAt': at.add(const Duration(days: 30)).toIso8601String(),
      'deviceId': uid(0x6, 1),
      'me': me(status: _status),
    };
  }

  Map<String, Object?> _basicRefusal() {
    final token = _token();
    _refusalTokens[token] = now().add(const Duration(hours: 1));
    return {
      'error': 'licence_basic',
      'message': 'This app needs an Advanced licence',
      'extension': '204',
      'extensionName': 'Warehouse',
      'refusalToken': token,
    };
  }

  Future<void> _deviceLimit(_Req r) => r.error(
    409,
    'device_limit',
    "You're signed in on 5 phones and computers already. Sign out a device first.",
  );

  /// What the account behind [email] gets once the code or link is right.
  Future<void> _finish(_Req r, String email) {
    if (email == SignInFixtures.basicEmail) return r.json(403, _basicRefusal());
    if (email == SignInFixtures.deviceLimitEmail) return _deviceLimit(r);
    return r.json(200, _session(email));
  }

  Future<void> _complete(_Req r) async {
    final body = await r.body();
    final hasCode = body['code'] is String;
    final hasLink = body['linkToken'] is String;
    if (hasCode == hasLink ||
        body['requestSecret'] is! String ||
        body['devicePublicKey'] is! String ||
        body['device'] is! Map) {
      return r.error(
        400,
        'validation',
        'Exactly one of code or linkToken, with the secret, key and device',
      );
    }
    final req = _requests[r.params[0]];
    // Without the secret of the phone that asked, nothing completes (APP1).
    if (req == null || req.secret != body['requestSecret']) {
      return r.error(
        410,
        'code_expired',
        'This sign-in has expired. Start again.',
      );
    }
    if (req.used) {
      return r.error(410, 'code_used', 'This code has been used. Start again.');
    }
    if (req.attempts >= 5) {
      return r.error(
        410,
        'request_locked',
        'Too many wrong codes. Start again.',
      );
    }
    if (now().isAfter(req.createdAt.add(const Duration(minutes: 10)))) {
      return r.error(
        410,
        'code_expired',
        'This code has expired. Send a new one.',
      );
    }
    // An unknown email never got a code, so no code is right for it.
    final known = SignInFixtures.knownEmails.contains(req.email);
    final ok =
        known &&
        (body['code'] == SignInFixtures.code ||
            body['linkToken'] == SignInFixtures.linkToken);
    if (!ok) {
      req.attempts++;
      final left = 5 - req.attempts;
      if (left == 0) {
        return r.error(
          410,
          'request_locked',
          'Too many wrong codes. Start again.',
        );
      }
      return r.error(
        400,
        'invalid_code',
        "That code isn't right. $left ${left == 1 ? 'try' : 'tries'} left.",
      );
    }
    req.used = true;
    return _finish(r, req.email);
  }

  Future<void> _qrComplete(_Req r) async {
    final body = await r.body();
    final token = body['qrToken'];
    if (token is! String || body['devicePublicKey'] is! String) {
      return r.error(
        400,
        'validation',
        'qrToken and devicePublicKey are required',
      );
    }
    if (_usedQr.contains(token)) {
      return r.error(
        410,
        'qr_used',
        'This QR code has been used. Make a new one in the portal.',
      );
    }
    final email = switch (token) {
      SignInFixtures.qrToken => SignInFixtures.advancedEmail,
      SignInFixtures.qrBasicToken => SignInFixtures.basicEmail,
      _ => null,
    };
    if (email == null) {
      return r.error(
        410,
        'qr_expired',
        'This QR code has expired. Make a new one in the portal.',
      );
    }
    _usedQr.add(token);
    return _finish(r, email);
  }

  Future<void> _refresh(_Req r) async {
    final body = await r.body();
    final token = body['refreshToken'];
    final ts = DateTime.tryParse('${body['timestamp']}');
    if (token is! String ||
        body['deviceId'] is! String ||
        ts == null ||
        body['signature'] is! String ||
        (body['signature'] as String).isEmpty) {
      return r.error(
        400,
        'validation',
        'deviceId, refreshToken, timestamp and signature are required',
      );
    }
    if (token == SignInFixtures.revokedRefreshToken) {
      return r.json(401, {
        'error': 'device_revoked',
        'message': "You've been signed out",
        'revokedBy': 'Priya Shah, your admin',
        'revokedAt': melb(27, 15, 12),
        'extension': '202',
        'support': support,
      });
    }
    if (token == SignInFixtures.basicRefreshToken) {
      return r.json(403, _basicRefusal());
    }
    if (ts.difference(now()).abs() > const Duration(minutes: 2)) {
      return r.error(400, 'validation', 'timestamp must be within 2 minutes');
    }
    final state = _refreshTokens[token];
    if (state == null) {
      return r.json(401, {
        'error': 'refresh_invalid',
        'message': 'Sign in again.',
      });
    }
    if (state.rotated) {
      // Reuse of an old refresh token revokes the device (theft signal).
      _refreshTokens.removeWhere((_, s) => s.email == state.email);
      return r.json(401, {
        'error': 'device_revoked',
        'message': "You've been signed out",
        'extension': '202',
        'support': support,
      });
    }
    state.rotated = true;
    final s = _session(state.email)
      ..remove('me')
      ..remove('deviceId');
    return r.json(200, s);
  }

  Future<void> _licenceRequest(_Req r) async {
    final body = await r.body();
    final expires = _refusalTokens[body['refusalToken']];
    if (expires == null || now().isAfter(expires)) {
      return r.error(410, 'refusal_expired', 'Start again to ask your admin.');
    }
    return r.empty(202);
  }

  // ----------------------------------------------------------------- me

  Future<void> _putStatus(_Req r) async {
    final body = await r.body();
    final s = body['status'];
    if (!const ['available', 'dnd', 'away'].contains(s)) {
      return r.error(400, 'validation', 'status');
    }
    _status = s as String;
    _setPresence('202', switch (_status) {
      'dnd' => 'dnd',
      'away' => 'away',
      _ => 'available',
    });
    return r.json(200, {
      'status': _status,
      if (body['dndUntil'] != null) 'dndUntil': body['dndUntil'],
      'changedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _patchCallSettings(_Req r) async {
    final body = await r.body();
    final next = {...callSettings, ...body}..removeWhere((k, v) => v == null);
    return r.json(200, next);
  }

  Future<void> _override(_Req r) async {
    if (r.params[0] != officeHoursId) {
      return r.error(404, 'not_found', 'Not found');
    }
    final body = await r.body();
    final mode = body['mode'];
    if (!const ['schedule', 'open', 'closed'].contains(mode)) {
      return r.error(400, 'validation', 'mode');
    }
    _officeMode = mode as String;
    return r.json(200, officeHours(_officeMode));
  }

  Future<void> _devices(_Req r) => r.json(200, [
    for (final d in devices)
      {...d, 'rings': _deviceRings[d['id']] ?? d['rings']},
  ]);

  Future<void> _patchDevice(_Req r) async {
    final d = devices.where((d) => d['id'] == r.params[0]).firstOrNull;
    if (d == null) return r.error(404, 'not_found', 'Not found');
    final body = await r.body();
    _deviceRings[d['id'] as String] = body['rings'] == true;
    return r.json(200, {...d, 'rings': body['rings'] == true});
  }

  Future<void> _signOutDevice(_Req r) {
    final d = devices.where((d) => d['id'] == r.params[0]).firstOrNull;
    if (d == null || d['canSignOut'] != true) {
      return r.error(404, 'not_found', 'Not found');
    }
    return r.empty(204);
  }

  Future<void> _sipCredentials(_Req r) {
    r.req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    return r.json(200, {
      'authUsername': 'mock-202-pixel8',
      // Random per call, as the real route rotates it. Mock only.
      'password': _token(),
      'domain': 'sip.demo-co.example',
      'outboundProxy': 'sip:sip.voiceplatform.example:5061;transport=tls',
      'displayName': 'Ava Nguyen',
      'expiresSeconds': 600,
      'pushParam': 'voiceplatform-app',
      // This device's own id, as the edge expects for +sip.instance.
      'instanceId': 'urn:uuid:${uid(0x6, 1)}',
    });
  }

  // ---------------------------------------------------------- directory

  Map<String, Object?> _presenceEntry(String ext) => {
    'extension': ext,
    'presence': _presence[ext],
    if (_presenceSince[ext] != null)
      'since': _presenceSince[ext]!.toIso8601String(),
  };

  Map<String, Object?> _colleague(Map<String, Object?> c) => {
    'userId': uid(0xa, c['n'] as int),
    'name': c['name'],
    'initials': c['initials'],
    'extension': '${c['n']}',
    if (c['team'] != null) 'team': c['team'],
    if (c['role'] != null) 'role': c['role'],
    if (c['mobile'] != null) 'mobile': c['mobile'],
    'presence': _presenceEntry('${c['n']}'),
  };

  Future<void> _colleagues(_Req r) => r.json(200, {
    'total': colleaguesTotal,
    'freeNow': _presence.values
        .where((p) => p == 'available' || p == 'mobile_only')
        .length,
    'items': [for (final c in colleagues) _colleague(c)],
  });

  Future<void> _sharedContacts(_Req r) {
    final q = r.query['q']?.toLowerCase();
    return r.json(200, [
      for (final c in sharedContacts)
        if (q == null ||
            (c['name'] as String).toLowerCase().contains(q) ||
            ((c['company'] as String?) ?? '').toLowerCase().contains(q))
          c,
    ]);
  }

  String get _presenceEtag =>
      '"${_presence.entries.map((e) => '${e.key}${e.value}').join().hashCode}"';

  Future<void> _presenceRoute(_Req r) {
    final etag = _presenceEtag;
    if (r.req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      return r.empty(304);
    }
    r.req.response.headers.set(HttpHeaders.etagHeader, etag);
    return r.json(200, [for (final ext in _presence.keys) _presenceEntry(ext)]);
  }

  void _setPresence(String ext, String presence) {
    if (_presence[ext] == presence) return;
    _presence[ext] = presence;
    if (presence == 'on_call') {
      _presenceSince[ext] = DateTime.now().toUtc();
    } else {
      _presenceSince.remove(ext);
    }
    _broadcast('presence', _presenceEntry(ext));
  }

  void _broadcast(String event, Object data) {
    final frame = 'event: $event\ndata: ${jsonEncode(data)}\n\n';
    for (final s in _streams) {
      s.add(frame);
    }
  }

  Future<void> _events(_Req r) async {
    r.done = true;
    final res = r.req.response
      ..statusCode = 200
      ..bufferOutput = false
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    // One stream per device: a second one closes the first (contract).
    for (final s in _streams.toList()) {
      await s.close();
    }
    final out = StreamController<String>();
    _streams.add(out);
    final heartbeat = Timer.periodic(
      heartbeatEvery,
      (_) => out.add(': keep-alive\n\n'),
    );
    out.add(
      'event: presence.snapshot\ndata: ${jsonEncode({
        'items': [for (final ext in _presence.keys) _presenceEntry(ext)],
      })}\n\n',
    );
    out.add(
      'event: badges\ndata: ${jsonEncode({'recents': 2, 'messages': 1 - _readThreads.length.clamp(0, 1)})}\n\n',
    );
    _scriptTimer ??= Timer.periodic(presenceEvery, (_) {
      if (_streams.isEmpty) return;
      final step = presenceScript[_scriptStep++ % presenceScript.length];
      _setPresence(step['extension']!, step['presence']!);
    });
    try {
      await res.addStream(out.stream.map(utf8.encode));
    } catch (_) {
      // Client went away.
    } finally {
      heartbeat.cancel();
      _streams.remove(out);
      if (_streams.isEmpty) {
        _scriptTimer?.cancel();
        _scriptTimer = null;
      }
      await res.close().catchError((_) {});
    }
  }

  // ------------------------------------------------------------ history

  Future<void> _page(
    _Req r,
    List<Map<String, Object?>> items, {
    Map<String, Object?> extra = const {},
  }) {
    final limit = (int.tryParse(r.query['limit'] ?? '') ?? 50).clamp(1, 100);
    final start = int.tryParse(r.query['before'] ?? '') ?? 0;
    final page = items.skip(start).take(limit).toList();
    final next = start + page.length < items.length
        ? '${start + page.length}'
        : null;
    return r.json(200, {'items': page, 'nextBefore': ?next, ...extra});
  }

  Future<void> _history(_Req r) {
    final filter = r.query['filter'] ?? 'all';
    final mine = r.query['mine'] == 'true';
    final items = [
      for (final h in history)
        if ((filter == 'all' ||
                (filter == 'missed' &&
                    (h['outcome'] == 'missed' ||
                        h['outcome'] == 'voicemail')) ||
                (filter == 'voicemail' && h['outcome'] == 'voicemail')) &&
            (!mine || h['mine'] == true))
          h,
    ];
    return _page(
      r,
      items,
      extra: {
        'counts': {'missed': 2, 'voicemail': 2},
      },
    );
  }

  // ---------------------------------------------------------- voicemail

  Map<String, Object?> _vm(Map<String, Object?> v) =>
      _heardChanged.contains(v['id'])
      ? {...v, 'heard': !(v['heard'] as bool)}
      : v;

  Future<void> _voicemails(_Req r) {
    final box = r.query['boxId'];
    final status = r.query['status'] ?? 'all';
    final items = [
      for (final v in voicemails.map(_vm))
        if (!_deletedVoicemail.contains(v['id']) &&
            (box == null || v['boxId'] == box) &&
            (status == 'all' || (status == 'new') == !(v['heard'] as bool)))
          v,
    ];
    return _page(r, items);
  }

  Map<String, Object?> _mediaUrl(String what) => {
    'url': '$basePath/media/${_token()}',
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  };

  Future<void> _voicemailMedia(_Req r) {
    if (!voicemails.any((v) => v['id'] == r.params[0]) ||
        _deletedVoicemail.contains(r.params[0])) {
      return r.error(404, 'not_found', 'Not found');
    }
    return r.json(200, _mediaUrl(r.params[0]));
  }

  Future<void> _voicemailRead(_Req r) async {
    final v = voicemails.where((v) => v['id'] == r.params[0]).firstOrNull;
    if (v == null) return r.error(404, 'not_found', 'Not found');
    final body = await r.body();
    final heard = body['heard'] == true;
    if (heard == v['heard']) {
      _heardChanged.remove(v['id']);
    } else {
      _heardChanged.add(v['id'] as String);
    }
    return r.empty(204);
  }

  Future<void> _voicemailDelete(_Req r) {
    if (!voicemails.any((v) => v['id'] == r.params[0])) {
      return r.error(404, 'not_found', 'Not found');
    }
    _deletedVoicemail.add(r.params[0]);
    return r.empty(204);
  }

  Future<void> _putGreeting(_Req r) async {
    final kind = r.params[0];
    if (!const ['unavailable', 'busy', 'name'].contains(kind)) {
      return r.error(404, 'not_found', 'Not found');
    }
    final bytes = await r.bytes();
    if (bytes.length > 5 * 1024 * 1024) {
      return r.error(413, 'greeting_too_large', 'Up to 5 MB');
    }
    return r.json(200, {
      'kind': kind,
      'isCustom': true,
      'durationSeconds': 5,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _pin(_Req r) async {
    final body = await r.body();
    final pin = body['pin'];
    if (pin is! String || !RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
      return r.error(400, 'validation', 'pin');
    }
    final same = pin.split('').toSet().length == 1;
    final seq = '0123456789'.contains(pin) || '9876543210'.contains(pin);
    if (same || seq) {
      return r.error(422, 'pin_weak', 'Avoid repeated or sequential digits');
    }
    return r.empty(204);
  }

  Future<void> _recordingMedia(_Req r) {
    if (!recordings.any((x) => x['id'] == r.params[0])) {
      return r.error(404, 'not_found', 'Not found');
    }
    return r.json(200, _mediaUrl(r.params[0]));
  }

  Future<void> _media(_Req r) async {
    r.done = true;
    final res = r.req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('audio', 'wav')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..add(_toneWav());
    await res.close();
  }

  /// One second of a quiet 440 Hz tone, 8 kHz mono 16-bit.
  static Uint8List _toneWav() {
    const rate = 8000;
    final data = ByteData(rate * 2);
    for (var i = 0; i < rate; i++) {
      data.setInt16(
        i * 2,
        (sin(2 * pi * 440 * i / rate) * 3000).round(),
        Endian.little,
      );
    }
    final h = ByteData(44);
    void s(int o, String t) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(o + i, t.codeUnitAt(i));
      }
    }

    s(0, 'RIFF');
    h.setUint32(4, 36 + rate * 2, Endian.little);
    s(8, 'WAVE');
    s(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, 1, Endian.little);
    h.setUint32(24, rate, Endian.little);
    h.setUint32(28, rate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    s(36, 'data');
    h.setUint32(40, rate * 2, Endian.little);
    return Uint8List.fromList([
      ...h.buffer.asUint8List(),
      ...data.buffer.asUint8List(),
    ]);
  }

  // ----------------------------------------------------------- messages

  Map<String, Object?> _thread(Map<String, Object?> t) =>
      _readThreads.contains(t['id']) ? {...t, 'unread': 0} : t;

  Future<void> _threads(_Req r) {
    final line = r.query['lineId'];
    final items = [
      for (final t in threads.map(_thread))
        if (line == null || t['lineId'] == line) t,
    ];
    final unread = items.fold<int>(0, (n, t) => n + (t['unread'] as int));
    return _page(r, items, extra: {'unreadTotal': unread});
  }

  Future<void> _threadMessages(_Req r) {
    final list = threadMessages[r.params[0]];
    if (list == null) return r.error(404, 'not_found', 'Not found');
    return _page(r, [
      ...list,
      ..._sent.where((m) => m['threadId'] == r.params[0]),
    ]);
  }

  Future<void> _readThread(_Req r) {
    if (!threads.any((t) => t['id'] == r.params[0])) {
      return r.error(404, 'not_found', 'Not found');
    }
    _readThreads.add(r.params[0]);
    _broadcast('badges', {'recents': 2, 'messages': 0});
    return r.empty(204);
  }

  Future<void> _send(_Req r) async {
    final body = await r.body();
    final text = body['text'];
    final line = smsLines.where((l) => l['id'] == body['lineId']).firstOrNull;
    if (line == null) {
      return r.error(403, 'no_permission', 'You cannot text from this line');
    }
    if (text is! String || text.isEmpty) {
      return r.error(400, 'validation', 'text');
    }
    if (text.length > 1530) {
      return r.error(422, 'too_long', 'More than 10 parts');
    }
    final thread = threads
        .where((t) => t['lineId'] == line['id'] && t['number'] == body['to'])
        .firstOrNull;
    final m = {
      'id': _uuid(),
      'threadId': thread?['id'] ?? _uuid(),
      'direction': 'out',
      'at': DateTime.now().toUtc().toIso8601String(),
      'kind': 'text',
      'text': text,
      'senderName': 'Ava',
      'status': 'queued',
    };
    _sent.add(m);
    return r.json(202, m);
  }
}

class _SignInRequest {
  _SignInRequest(this.email, this.secret, DateTime at)
    : createdAt = at,
      sentAt = at;
  final String email;
  final String secret;
  DateTime createdAt;
  DateTime sentAt;
  int attempts = 0;
  bool used = false;
}

class _RefreshState {
  _RefreshState(this.email);
  final String email;
  bool rotated = false;
}

class _Req {
  _Req(this.req);
  final HttpRequest req;
  List<String> params = const [];
  bool done = false;

  Map<String, String> get query => req.uri.queryParameters;

  Uint8List? _bytes;

  Future<Uint8List> bytes() async {
    if (_bytes != null) return _bytes!;
    final b = BytesBuilder(copy: false);
    await for (final chunk in req) {
      b.add(chunk);
    }
    return _bytes = b.takeBytes();
  }

  Future<Map<String, Object?>> body() async {
    final raw = utf8.decode(await bytes());
    if (raw.isEmpty) return {};
    final v = jsonDecode(raw);
    return v is Map<String, Object?> ? v : {};
  }

  Future<void> json(int status, Object? body) async {
    done = true;
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> empty(int status) async {
    done = true;
    req.response.statusCode = status;
    await req.response.close();
  }

  Future<void> error(int status, String code, String message) =>
      json(status, {'error': code, 'message': message});
}
