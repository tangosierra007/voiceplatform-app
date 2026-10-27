import 'dart:convert';

/// The on-device scrubber for diagnostics (spec 22 Diagnostics, decision 140;
/// APP9, APP12). Every event, breadcrumb and attachment passes through it
/// before it is queued or sent to GlitchTip.
///
/// Text rules (`scrub`), in this order:
/// - exact secrets registered at run time (the SIP password, tokens) and
///   values from the phone's address book (replaced by `[contact]`);
/// - SIP `Authorization` and `Proxy-Authorization` header values, and digest
///   parameters (`response`, `nonce`, `cnonce`, `nextnonce`, `rspauth`,
///   `opaque`, `nc`);
/// - password-like and token-like key/value pairs, also as JSON keys
///   (`"password":`, `"token":`, `accessToken`, `refresh_token`,
///   `requestSecret`, `pn-prid`, ...); `Bearer` tokens;
/// - App Link and QR tokens (`/app/signin/<id>/<token>`,
///   `vpapp://signin/<token>`), media tokens (`/app/v1/media/<token>`) and
///   secret query parameters;
/// - email addresses (SIP URIs are kept);
/// - long opaque strings (32 or more base64url or hex characters, with both
///   letters and digits: request secrets, keys);
/// - runs of 6 or more digits, which may be broken by up to two spaces,
///   dashes, dots, slashes or brackets (phone numbers, 6-digit codes).
///   Dotted IPv4 addresses are kept.
///
/// The SIP rules, placeholders and digit rule are the same as vp_linphone's
/// `LogScrubber`, so the shared cases in `test/diagnostics/shared_scrub_cases.dart`
/// give the same output from both.
///
/// Structured data (`scrubJson`): any key naming the address book or contacts
/// is dropped with its value (APP12); secret-named keys keep their name and
/// lose their value; every other string is scrubbed as text, except the SDK's
/// own structural fields (ids, timestamps, release, stack frames, device and
/// OS contexts).
final class DiagnosticsScrubber {
  DiagnosticsScrubber();

  /// The app's one scrubber; the engine and the contacts feature register
  /// their secrets and address-book values here (in memory only).
  static final DiagnosticsScrubber instance = DiagnosticsScrubber();

  static const redacted = '[scrubbed]';
  static const number = '[n]';
  static const email = '[email]';
  static const contact = '[contact]';

  final Set<String> _secrets = {};
  final Set<String> _addressBook = {};

  /// Values that must never leave the device as they are (for example the SIP
  /// password once known). Values shorter than 4 characters are ignored.
  void addSecret(String value) {
    if (value.length >= 4) _secrets.add(value);
  }

  /// Names, numbers and other values read from the phone's address book.
  /// Held in memory only; replaced by `[contact]` wherever they appear.
  void rememberAddressBookValues(Iterable<String> values) {
    _addressBook.addAll(values.map((v) => v.trim()).where((v) => v.length >= 2));
  }

  void forgetAddressBookValues() => _addressBook.clear();

  void clearSecrets() => _secrets.clear();

  static final List<(RegExp, String Function(Match))> _rules = [
    // SIP digest headers: the whole value goes.
    (RegExp(r'\b((?:Proxy-)?Authorization\s*:)[^\r\n]*', caseSensitive: false), (m) => '${m[1]} $redacted'),
    (
      RegExp(r'\b(response|rspauth|nextnonce|cnonce|nonce|opaque|nc)\s*=\s*("[^"]*"|[^,\s;>]+)', caseSensitive: false),
      (m) => '${m[1]}=$redacted',
    ),
    // Password-like pairs, also as JSON keys.
    (
      RegExp(
        r'\b(password|passwd|pass|pwd|ha1|secret|request_?secret|sip_?password)("?\s*[=:]\s*)("[^"]*"|[^\s,;&>"}]+)',
        caseSensitive: false,
      ),
      (m) => '${m[1]}${m[2]}$redacted',
    ),
    // Token-like pairs: token, access_token, refreshToken, linkToken, pn-prid ...
    (
      RegExp(r'\b(pn-prid|prid|\w*token)("?\s*[=:]\s*)("[^"]*"|[^;,\s>&"}]+)', caseSensitive: false),
      (m) => '${m[1]}${m[2]}$redacted',
    ),
    (RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false), (_) => 'Bearer $redacted'),
    // App Link, QR and media tokens.
    (RegExp(r'(/app/signin/)[^\s/?#"' "'" r'<>]+(?:/[^\s/?#"' "'" r'<>]+)?'), (m) => '${m[1]}$redacted'),
    (RegExp(r'(vpapp://signin/)[^\s?#"' "'" r'<>]+', caseSensitive: false), (m) => '${m[1]}$redacted'),
    (RegExp(r'(/app/v1/media/)[^\s/?#"' "'" r'<>]+'), (m) => '${m[1]}$redacted'),
    (
      RegExp(r'([?&](?:code|sig|signature|key|secret|X-Amz-[\w-]+)=)[^&#\s"' "'" r'<>]+', caseSensitive: false),
      (m) => '${m[1]}$redacted',
    ),
    // Email addresses; SIP and tel URIs are kept.
    (RegExp(r'(?<![\w.%+-])(?<!sips:)(?<!sip:)(?<!tel:)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), (_) => email),
  ];

  // Long opaque values: 32+ base64url/hex characters holding letters and digits.
  static final _opaque = RegExp(r'(?<![A-Za-z0-9_-])(?=[A-Za-z_-]*\d)(?=[\d_-]*[A-Za-z])[A-Za-z0-9_-]{32,}={0,2}');
  static final _digits = RegExp(r'\+?\d(?:[ ()\-./]{0,2}\d){5,}');
  static final _ipv4 = RegExp(r'^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$');

  /// Scrubs free text.
  String scrub(String text) {
    var out = text;
    for (final s in _sortedLongestFirst(_secrets)) {
      out = out.replaceAll(s, redacted);
    }
    for (final v in _sortedLongestFirst(_addressBook)) {
      out = out.replaceAll(RegExp(RegExp.escape(v), caseSensitive: false), contact);
    }
    for (final (regex, replace) in _rules) {
      out = out.replaceAllMapped(regex, replace);
    }
    out = out.replaceAll(_opaque, redacted);
    // Phone numbers and codes last; a dotted IPv4 address is kept.
    return out.replaceAllMapped(_digits, (m) => _ipv4.hasMatch(m[0]!) ? m[0]! : number);
  }

  static List<String> _sortedLongestFirst(Set<String> s) => s.toList()..sort((a, b) => b.length.compareTo(a.length));

  /// A key naming the phone's address book or its contacts (APP12).
  static final addressBookKey = RegExp(r'contact|address[\s_-]?book|phone[\s_-]?book|vcard', caseSensitive: false);

  // Keys whose value is always secret, whatever it looks like.
  static final _secretKey = RegExp(
    r'^(?:(?:proxy-)?authorization|cookie|set-cookie|x-api-key|password|passwd|pwd|ha1|secret|request_?secret|sip_?password|.*token|pn-prid|prid)$',
    caseSensitive: false,
  );

  static final _codeKey = RegExp(r'^(?:\w*_)?(?:code|otp|pin)$', caseSensitive: false);

  // SDK structural fields kept as they are (no user data; scrubbing would
  // mangle them, for example timestamps into `[n]`).
  static const _keepValue = {
    'event_id',
    'timestamp',
    'start_timestamp',
    'release',
    'dist',
    'environment',
    'platform',
    'level',
    'logger',
    'type',
    'mechanism',
    'sdk',
    'debug_meta',
    'modules',
    'stacktrace',
    'threads',
    'trace_id',
    'span_id',
    'parent_span_id',
  };

  // Standard contexts filled by the SDK from the device; kept except for the
  // device's own name, which a user may have set to their name.
  static const _sdkContexts = {'os', 'device', 'app', 'runtime', 'runtimes', 'culture', 'trace', 'flutter_context', 'dart_context'};

  /// Scrubs a JSON-like value (maps, lists, strings).
  Object? scrubJson(Object? value) {
    if (value is String) return scrub(value);
    if (value is List) return [for (final v in value) scrubJson(v)];
    if (value is Map) {
      final out = <String, Object?>{};
      value.forEach((k, v) {
        final key = '$k';
        if (addressBookKey.hasMatch(key)) return;
        if (_keepValue.contains(key)) {
          out[key] = v;
        } else if (_secretKey.hasMatch(key) && (v is String || v is num)) {
          out[key] = redacted;
        } else if (_codeKey.hasMatch(key) && (v is num || (v is String && v.contains(RegExp(r'\d'))))) {
          // Sign-in codes and PINs; an error code such as update_required stays.
          out[key] = redacted;
        } else {
          out[key] = scrubJson(v);
        }
      });
      return out;
    }
    return value;
  }

  /// Scrubs a serialised Sentry event (`SentryEvent.toJson()` or an envelope
  /// item). No user, no server name, no cookies; contexts as described above.
  Map<String, dynamic> scrubEventJson(Map<String, dynamic> event) {
    final e = Map<String, dynamic>.of(event)
      ..remove('user')
      ..remove('server_name');
    final contexts = e.remove('contexts');
    final request = e.remove('request');
    final out = (scrubJson(e) as Map).cast<String, dynamic>();
    if (contexts is Map) {
      final c = <String, dynamic>{};
      contexts.forEach((k, v) {
        final key = '$k';
        if (addressBookKey.hasMatch(key)) return;
        if (_sdkContexts.contains(key) && v is Map) {
          c[key] = key == 'device' ? (Map<String, dynamic>.from(v)..remove('name')) : v;
        } else {
          c[key] = scrubJson(v);
        }
      });
      out['contexts'] = c;
    }
    if (request is Map) {
      final r = (scrubJson(Map<String, dynamic>.from(request)..remove('cookies')) as Map).cast<String, dynamic>();
      out['request'] = r;
    }
    if (out['breadcrumbs'] is List) {
      out['breadcrumbs'] = [
        for (final b in out['breadcrumbs'] as List)
          if (b is Map && !isAddressBookBreadcrumb(b)) b,
      ];
    } else if (out['breadcrumbs'] is Map && (out['breadcrumbs'] as Map)['values'] is List) {
      final values = (out['breadcrumbs'] as Map)['values'] as List;
      out['breadcrumbs'] = {
        'values': [
          for (final b in values)
            if (b is Map && !isAddressBookBreadcrumb(b)) b,
        ],
      };
    }
    return out;
  }

  /// A breadcrumb about the address book is dropped whole (APP12).
  static bool isAddressBookBreadcrumb(Map<dynamic, dynamic> b) =>
      addressBookKey.hasMatch('${b['category'] ?? ''}') || addressBookKey.hasMatch('${b['type'] ?? ''}');

  /// Scrubs a serialised breadcrumb; null means drop it.
  Map<String, dynamic>? scrubBreadcrumbJson(Map<String, dynamic> b) {
    if (isAddressBookBreadcrumb(b)) return null;
    return (scrubJson(b) as Map).cast<String, dynamic>();
  }

  /// Attachments: text (logs, JSON) is scrubbed as text; anything else is
  /// dropped, as it can't be checked. Returns null to drop.
  List<int>? scrubAttachment({required String filename, String? contentType, required List<int> bytes}) {
    if (addressBookKey.hasMatch(filename)) return null;
    final type = (contentType ?? '').toLowerCase();
    final name = filename.toLowerCase();
    final isText =
        type.startsWith('text/') ||
        type.contains('json') ||
        name.endsWith('.txt') ||
        name.endsWith('.log') ||
        name.endsWith('.json');
    if (!isText || type.contains('gzip') || name.endsWith('.gz')) return null;
    return utf8.encode(scrub(utf8.decode(bytes, allowMalformed: true)));
  }
}
