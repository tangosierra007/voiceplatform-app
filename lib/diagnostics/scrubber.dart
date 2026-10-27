import 'dart:convert';

/// The on-device scrubber for diagnostics (spec 22 Diagnostics, decision 140;
/// APP9, APP12). Every event, breadcrumb and attachment passes through it
/// before it is queued or sent to GlitchTip.
///
/// Text rules (`scrub`), in this order:
/// - exact secrets registered at run time (the SIP password, tokens);
/// - values from the phone's address book and their name parts, as whole
///   words, any case, any whitespace (replaced by `[contact]`);
/// - header values of `Authorization`, `Proxy-Authorization`, `Cookie`,
///   `Set-Cookie` and `X-Api-Key`, and SIP digest parameters (`response`,
///   `nonce`, `cnonce`, `nextnonce`, `rspauth`, `opaque`, `nc`);
/// - key/value pairs whose key contains password, passwd, secret or token
///   (`newPassword`, `client_secret`, `refreshToken` ...), or is pass, pwd,
///   ha1, pn-prid or prid; keys may be quoted with `"` or `'`, values may be
///   quoted with either too; `Bearer` tokens;
/// - App Link and QR tokens (`/app/signin/<id>/<token>`,
///   `vpapp://signin/<token>`), media tokens (`/app/v1/media/<token>`) and
///   secret query parameters;
/// - email addresses (SIP URIs are kept);
/// - long opaque strings (32 or more base64url or hex characters, with both
///   letters and digits: request secrets, keys);
/// - runs of 6 or more digits, which may be broken by up to three spaces,
///   dashes, dots, slashes or brackets between digits (phone numbers, 6-digit
///   codes). Dotted IPv4 addresses are kept.
///
/// The placeholders and SIP rules match vp_linphone's `LogScrubber`; the
/// cases in `test/diagnostics/shared_scrub_cases.dart` give the same output
/// from both. This scrubber is wider (compound keys, single quotes, more
/// headers, three separators).
///
/// Structured data (`scrubJson`, `scrubEventJson`): any key naming the address
/// book or contacts is dropped with its value (APP12); secret-named keys keep
/// their name and lose their value; every other string is scrubbed as text.
/// Only the SDK's own fields at their known places in an event are kept as
/// they are (top-level ids, timestamps, release; exception type and stack
/// trace; breadcrumb timestamp, level and type; device and OS contexts).
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
  RegExp? _addressBookPattern;

  /// Values that must never leave the device as they are (for example the SIP
  /// password once known). Values shorter than 4 characters are ignored.
  void addSecret(String value) {
    if (value.length >= 4) _secrets.add(value);
  }

  void clearSecrets() => _secrets.clear();

  /// Names, numbers and other values read from the phone's address book, held
  /// in memory only. Each value and each of its words of 3 or more characters
  /// is replaced by `[contact]` wherever it appears as a whole word.
  void rememberAddressBookValues(Iterable<String> values) {
    for (final v in values) {
      final value = v.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (value.length >= 3) _addressBook.add(value);
      for (final part in value.split(' ')) {
        if (part.length >= 3) _addressBook.add(part);
      }
    }
    _rebuildAddressBookPattern();
  }

  void forgetAddressBookValues() {
    _addressBook.clear();
    _addressBookPattern = null;
  }

  void _rebuildAddressBookPattern() {
    if (_addressBook.isEmpty) {
      _addressBookPattern = null;
      return;
    }
    final alternatives = (_addressBook.toList()..sort((a, b) => b.length.compareTo(a.length)))
        .map((v) => v.split(' ').map(RegExp.escape).join(r'\s+'))
        .join('|');
    _addressBookPattern = RegExp(
      r'(?<![\p{L}\p{N}_])(?:' + alternatives + r')(?![\p{L}\p{N}_])',
      caseSensitive: false,
      unicode: true,
    );
  }

  static const _value = r'''("[^"]*"|'[^']*'|[^\s,;&>"'}]+)''';

  static final List<(RegExp, String Function(Match))> _rules = [
    // Header values: the whole value goes.
    (
      RegExp(r'''\b((?:Proxy-)?Authorization|Set-Cookie|Cookie|X-Api-Key)(["']?\s*:)[^\r\n]*''', caseSensitive: false),
      (m) => '${m[1]}${m[2]} $redacted',
    ),
    (
      RegExp(r'''\b(response|rspauth|nextnonce|cnonce|nonce|opaque|nc)\s*=\s*("[^"]*"|'[^']*'|[^,\s;>]+)''', caseSensitive: false),
      (m) => '${m[1]}=$redacted',
    ),
    // Password, secret and token pairs, with plain or quoted keys and values.
    (
      RegExp(r'''\b(\w*(?:password|passwd|secret|token)|pass|pwd|ha1|pn-prid|prid)(["']?\s*[=:]\s*)''' + _value, caseSensitive: false),
      (m) => '${m[1]}${m[2]}$redacted',
    ),
    (RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false), (_) => 'Bearer $redacted'),
    // App Link, QR and media tokens.
    (RegExp(r'''(/app/signin/)[^\s/?#"'<>]+(?:/[^\s/?#"'<>]+)?'''), (m) => '${m[1]}$redacted'),
    (RegExp(r'''(vpapp://signin/)[^\s?#"'<>]+''', caseSensitive: false), (m) => '${m[1]}$redacted'),
    (RegExp(r'''(/app/v1/media/)[^\s/?#"'<>]+'''), (m) => '${m[1]}$redacted'),
    (
      RegExp(r'''([?&](?:code|sig|signature|key|secret|X-Amz-[\w-]+)=)[^&#\s"'<>]+''', caseSensitive: false),
      (m) => '${m[1]}$redacted',
    ),
    // Email addresses; SIP and tel URIs are kept.
    (RegExp(r'(?<![\w.%+-])(?<!sips:)(?<!sip:)(?<!tel:)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), (_) => email),
  ];

  // Long opaque values: 32+ base64url/hex characters holding letters and digits.
  static final _opaque = RegExp(r'(?<![A-Za-z0-9_-])(?=[A-Za-z_-]*\d)(?=[\d_-]*[A-Za-z])[A-Za-z0-9_-]{32,}={0,2}');
  static final _digits = RegExp(r'\+?\d(?:[ ()\-./]{0,3}\d){5,}');
  static final _ipv4 = RegExp(r'^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$');

  /// Scrubs free text.
  String scrub(String text) {
    var out = text;
    for (final s in _secrets.toList()..sort((a, b) => b.length.compareTo(a.length))) {
      out = out.replaceAll(s, redacted);
    }
    final book = _addressBookPattern;
    if (book != null) out = out.replaceAll(book, contact);
    for (final (regex, replace) in _rules) {
      out = out.replaceAllMapped(regex, replace);
    }
    out = out.replaceAll(_opaque, redacted);
    // Phone numbers and codes last; a dotted IPv4 address is kept.
    return out.replaceAllMapped(_digits, (m) => _ipv4.hasMatch(m[0]!) ? m[0]! : number);
  }

  /// A key naming the phone's address book or its contacts (APP12).
  static final addressBookKey = RegExp(r'contact|address[\s_-]?book|phone[\s_-]?book|vcard', caseSensitive: false);

  // Keys whose value is always secret, whatever it looks like.
  static final _secretKey = RegExp(
    r'^(?:(?:proxy-)?authorization|cookie|set-cookie|x-api-key|[\w-]*(?:password|passwd|secret|token)|pass|pwd|ha1|pn-prid|prid)$',
    caseSensitive: false,
  );

  static final _codeKey = RegExp(r'^(?:\w*_)?(?:code|otp|pin)$', caseSensitive: false);

  // SDK fields kept as they are, only at these places in an event (scrubbing
  // would mangle them, for example timestamps into `[n]`).
  static const _keepTopLevel = {
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
    'sdk',
    'debug_meta',
    'modules',
    'threads',
  };
  static const _keepInException = {'type', 'module', 'mechanism', 'stacktrace', 'thread_id'};
  static const _keepInBreadcrumb = {'timestamp', 'level', 'type'};

  // Standard contexts filled by the SDK from the device; kept except for the
  // device's own name, which a user may have set to their name.
  static const _sdkContexts = {'os', 'device', 'app', 'runtime', 'runtimes', 'culture', 'trace', 'flutter_context', 'dart_context'};

  /// Scrubs a JSON-like value (maps, lists, strings). Keys in [keep] at this
  /// level only are copied as they are.
  Object? scrubJson(Object? value, {Set<String> keep = const {}}) {
    if (value is String) return scrub(value);
    if (value is List) return [for (final v in value) scrubJson(v)];
    if (value is Map) {
      final out = <String, Object?>{};
      value.forEach((k, v) {
        final key = '$k';
        if (addressBookKey.hasMatch(key)) return;
        if (keep.contains(key)) {
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
    final exception = e.remove('exception');
    final breadcrumbs = e.remove('breadcrumbs');
    final out = (scrubJson(e, keep: _keepTopLevel) as Map).cast<String, dynamic>();

    if (exception is Map) {
      final x = (scrubJson(Map<String, dynamic>.from(exception)..remove('values')) as Map).cast<String, dynamic>();
      final values = exception['values'];
      if (values is List) {
        x['values'] = [for (final v in values) v is Map ? scrubJson(v, keep: _keepInException) : scrubJson(v)];
      }
      out['exception'] = x;
    }
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
      out['request'] = (scrubJson(Map<String, dynamic>.from(request)..remove('cookies')) as Map).cast<String, dynamic>();
    }
    List<Object?> crumbs(List<Object?> list) => [
      for (final b in list)
        if (b is Map && !isAddressBookBreadcrumb(b)) scrubJson(b, keep: _keepInBreadcrumb),
    ];
    if (breadcrumbs is List) {
      out['breadcrumbs'] = crumbs(breadcrumbs);
    } else if (breadcrumbs is Map && breadcrumbs['values'] is List) {
      out['breadcrumbs'] = {'values': crumbs(breadcrumbs['values'] as List)};
    }
    return out;
  }

  /// A breadcrumb about the address book is dropped whole (APP12).
  static bool isAddressBookBreadcrumb(Map<dynamic, dynamic> b) =>
      addressBookKey.hasMatch('${b['category'] ?? ''}') || addressBookKey.hasMatch('${b['type'] ?? ''}');

  /// Scrubs a serialised breadcrumb; null means drop it.
  Map<String, dynamic>? scrubBreadcrumbJson(Map<String, dynamic> b) {
    if (isAddressBookBreadcrumb(b)) return null;
    return (scrubJson(b, keep: _keepInBreadcrumb) as Map).cast<String, dynamic>();
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
