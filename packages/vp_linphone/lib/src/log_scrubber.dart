/// Removes secrets and personal data from log text (spec 22, Diagnostics;
/// APP4, APP9). Mirrors the Kotlin log sink's scrubber
/// (`android/.../LogScrubber.kt`), which scrubs every line before it is
/// written; this one scrubs the exported bytes again on the Dart side.
///
/// Removed: SIP Authorization and Proxy-Authorization values, digest
/// parameters (including nextnonce and rspauth), password-like key/value pairs
/// (also as JSON keys), push tokens (pn-prid) and other tokens, bearer tokens,
/// any exact [secrets], email addresses (SIP URIs are kept), and runs of 6 or
/// more digits (phone numbers), which may be broken by up to two spaces,
/// dashes, dots, slashes or brackets. Dotted IPv4 addresses are kept.
final class LogScrubber {
  LogScrubber({Iterable<String> secrets = const []})
    : _secrets = secrets.where((s) => s.length >= 4).toList()..sort((a, b) => b.length.compareTo(a.length));

  static const redacted = '[scrubbed]';
  static const number = '[n]';
  static const email = '[email]';

  final List<String> _secrets;

  static final List<(RegExp, String Function(Match))> _rules = [
    (RegExp(r'\b((?:Proxy-)?Authorization\s*:)[^\r\n]*', caseSensitive: false), (m) => '${m[1]} $redacted'),
    (
      RegExp(r'\b(response|rspauth|nextnonce|cnonce|nonce|opaque|nc)\s*=\s*("[^"]*"|[^,\s;>]+)', caseSensitive: false),
      (m) => '${m[1]}=$redacted',
    ),
    (
      RegExp(r'\b(password|passwd|pass|pwd|ha1|secret)("?\s*[=:]\s*)("[^"]*"|[^\s,;&>"}]+)', caseSensitive: false),
      (m) => '${m[1]}${m[2]}$redacted',
    ),
    (
      RegExp(
        r'\b(pn-prid|prid|token|access_token|refresh_token)("?\s*[=:]\s*)("[^"]*"|[^;,\s>&"}]+)',
        caseSensitive: false,
      ),
      (m) => '${m[1]}${m[2]}$redacted',
    ),
    (RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false), (_) => 'Bearer $redacted'),
    (RegExp(r'(?<![\w.%+-])(?<!sips:)(?<!sip:)(?<!tel:)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), (_) => email),
  ];

  static final _digits = RegExp(r'\+?\d(?:[ ()\-./]{0,2}\d){5,}');
  static final _ipv4 = RegExp(r'^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$');

  String scrub(String text) {
    var out = text;
    for (final s in _secrets) {
      out = out.replaceAll(s, redacted);
    }
    for (final (regex, replace) in _rules) {
      out = out.replaceAllMapped(regex, replace);
    }
    // Phone numbers last; a dotted IPv4 address is kept.
    return out.replaceAllMapped(_digits, (m) => _ipv4.hasMatch(m[0]!) ? m[0]! : number);
  }
}
