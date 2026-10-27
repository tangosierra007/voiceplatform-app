import 'package:call_engine/call_engine.dart';

/// Parses the X-VP-* headers the platform puts on an INVITE to app contacts
/// (spec 22, Push and the incoming call path: A7, B27) into [IncomingInfo].
///
/// Formats assumed (documented in the handback for WS2, which emits them):
///
/// ```
/// X-VP-Called: +61355501201;label="Sales group"
/// X-VP-Also-Ringing: "Mia's desk phone", "Front desk DECT"
/// X-VP-Repeat: 3
/// X-VP-Last-Answered: "Mia Chen";at=2026-10-27T03:15:00Z
/// ```
///
/// - Quoted strings follow RFC 3261 (`\"` and `\\` escapes); an unquoted
///   token is accepted wherever a quoted string is.
/// - The number in X-VP-Called is E.164 (`+` and 2 to 15 digits) or left out
///   (`;label="Sales group"` alone).
/// - `at` is RFC 3339 with `Z` or an offset.
///
/// Parsing never throws: a malformed header just leaves its field empty, so
/// the incoming screen shows no tag rather than a wrong one.
abstract final class IncomingHeaders {
  static const int maxText = 64;
  static const int maxAlsoRinging = 5;
  static const int maxRepeat = 9999;

  static IncomingInfo parse({String? called, String? alsoRinging, String? repeat, String? lastAnswered}) {
    final c = parseCalled(called);
    final last = parseLastAnswered(lastAnswered);
    return IncomingInfo(
      calledNumber: c.number,
      calledLabel: c.label,
      alsoRinging: parseAlsoRinging(alsoRinging),
      repeatCount: parseRepeat(repeat),
      lastAnsweredBy: last.name,
      lastAnsweredAt: last.at,
    );
  }

  static final RegExp _e164 = RegExp(r'^\+[1-9]\d{1,14}$');

  static ({String? number, String? label}) parseCalled(String? value) {
    if (value == null || value.trim().isEmpty) return (number: null, label: null);
    final r = _Reader(value);
    final first = r.readValue(stopAtComma: false);
    final params = r.readParams();
    final number = first != null && _e164.hasMatch(first) ? first : null;
    return (number: number, label: _text(params['label']));
  }

  static List<String> parseAlsoRinging(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final r = _Reader(value);
    final out = <String>[];
    while (!r.atEnd) {
      final item = _text(r.readValue(stopAtComma: true));
      r.skipTo(',');
      if (item != null && !out.contains(item)) out.add(item);
      if (out.length == maxAlsoRinging) break;
    }
    return List.unmodifiable(out);
  }

  static int? parseRepeat(String? value) {
    final v = value?.trim();
    if (v == null || !RegExp(r'^\d{1,4}$').hasMatch(v)) return null;
    final n = int.parse(v);
    return n >= 1 && n <= maxRepeat ? n : null;
  }

  static final RegExp _zone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

  static ({String? name, DateTime? at}) parseLastAnswered(String? value) {
    if (value == null || value.trim().isEmpty) return (name: null, at: null);
    final r = _Reader(value);
    final name = _text(r.readValue(stopAtComma: false));
    final at = r.readParams()['at'];
    DateTime? when;
    if (at != null && _zone.hasMatch(at)) when = DateTime.tryParse(at)?.toUtc();
    return (name: name, at: when);
  }

  static final RegExp _control = RegExp(r'[\u0000-\u001f\u007f]');

  /// Display text: control characters removed, trimmed, at most [maxText].
  static String? _text(String? s) {
    if (s == null) return null;
    var t = s.replaceAll(_control, '').trim();
    if (t.isEmpty) return null;
    if (t.length > maxText) t = t.substring(0, maxText).trimRight();
    return t;
  }
}

/// A small reader for `value;param=value;param="quoted"` and comma lists.
class _Reader {
  _Reader(this.s);
  final String s;
  int i = 0;

  bool get atEnd => i >= s.length;

  void _skipWs() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  /// A quoted string or a token, up to `;` (and `,` when [stopAtComma]).
  String? readValue({required bool stopAtComma}) {
    _skipWs();
    if (atEnd) return null;
    if (s[i] == '"') return _quoted();
    final start = i;
    while (i < s.length && s[i] != ';' && !(stopAtComma && s[i] == ',')) {
      i++;
    }
    final t = s.substring(start, i).trim();
    return t.isEmpty ? null : t;
  }

  String _quoted() {
    i++; // opening quote
    final b = StringBuffer();
    while (i < s.length && s[i] != '"') {
      if (s[i] == r'\' && i + 1 < s.length) i++;
      b.write(s[i]);
      i++;
    }
    if (i < s.length) i++; // closing quote
    return b.toString();
  }

  /// `;name=value` pairs until the end (names lower-cased).
  Map<String, String> readParams() {
    final out = <String, String>{};
    while (true) {
      skipTo(';');
      if (atEnd) return out;
      i++; // ';'
      _skipWs();
      final start = i;
      while (i < s.length && s[i] != '=' && s[i] != ';') {
        i++;
      }
      final name = s.substring(start, i).trim().toLowerCase();
      String? value;
      if (i < s.length && s[i] == '=') {
        i++;
        value = readValue(stopAtComma: false);
      }
      if (name.isNotEmpty && value != null) out.putIfAbsent(name, () => value!);
    }
  }

  /// Moves to the next [c] outside quotes, or to the end; consumes a `,`.
  void skipTo(String c) {
    while (i < s.length && s[i] != c) {
      if (s[i] == '"') {
        _quoted();
      } else {
        i++;
      }
    }
    if (c == ',' && i < s.length) i++;
  }
}
