// The allow-list for check_phone_numbers: digit strings that look like an
// Australian phone number but are not one (a version, a long ID).
//
// One entry per line in allow_list.txt:
//
//   <path or commit:<short hash>>  <key>  # <reason, required>
//
// The key is allowKey() of the number's national digits, so the file never
// holds the number itself. Get it with
// `dart tool/check_phone_numbers.dart --print-allow-keys` on your own
// machine; CI never prints keys. A key is easy to reverse for a real phone
// number, so never allow-list one: replace it with an ACMA fictional number.

/// FNV-1a 64-bit of [national], as 16 hex digits.
String allowKey(String national) {
  var h = 0xcbf29ce484222325;
  for (final c in national.codeUnits) {
    h ^= c;
    h *= 0x100000001b3; // wraps at 64 bits on the Dart VM
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

class AllowList {
  AllowList._(this._entries);

  /// Parses allow_list.txt. Throws [FormatException] on an entry without a
  /// reason or with a malformed key.
  factory AllowList.parse(String text) {
    final entries = <String>{};
    final lines = text.split('\n');
    for (var n = 0; n < lines.length; n++) {
      final line = lines[n].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final hash = line.indexOf('#');
      final reason = hash < 0 ? '' : line.substring(hash + 1).trim();
      final fields = (hash < 0 ? line : line.substring(0, hash))
          .trim()
          .split(RegExp(r'\s+'));
      if (fields.length != 2 ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(fields[1]) ||
          reason.isEmpty) {
        throw FormatException(
            'allow_list.txt line ${n + 1}: want "<path> <16 hex key> # reason"');
      }
      entries.add('${fields[0]} ${fields[1]}');
    }
    return AllowList._(entries);
  }

  final Set<String> _entries;

  bool allows(String path, String national) =>
      _entries.contains('$path ${allowKey(national)}');
}
