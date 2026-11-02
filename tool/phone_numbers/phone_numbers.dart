// Finds Australian phone numbers in text and tells ACMA's fictional numbers
// apart from real ones. Used by tool/check_phone_numbers.dart (CI) and its
// tests in test/tool/. Only dart: libraries, so CI can run it without
// `pub get`.
//
// Allow-list source, copied exactly (page modified 3 September 2026, read
// 2 November 2026):
//   ACMA, "Phone numbers for use in TV shows, films and creative works",
//   https://www.acma.gov.au/phone-numbers-use-tv-shows-films-and-creative-works
// If ACMA changes the page, change the lists below to match it, never by
// guessing a range.
//
// This file must never hold a matchable number itself: every list below is
// written as digit groups that the scanner cannot read as a phone number.

/// What kind of number a hit is.
enum AuNumberKind {
  mobile('mobile'),
  geographic('geographic'),
  freephone('1800'),
  localRate('1300'),
  localRateShort('13');

  const AuNumberKind(this.label);
  final String label;
}

/// One Australian phone number found in a line of text.
class PhoneHit {
  PhoneHit({
    required this.start,
    required this.end,
    required this.text,
    required this.national,
    required this.kind,
  });

  /// Offsets of the hit in the scanned line.
  final int start;
  final int end;

  /// The hit exactly as written. Never print it; print [masked].
  final String text;

  /// Digits only, in national form (0412..., 02..., 1800..., 13...).
  final String national;
  final AuNumberKind kind;

  /// True when ACMA reserves this number for fiction.
  bool get isFictional => isAcmaFictional(national);

  /// The hit with all but its prefix and last three digits replaced by `x`,
  /// keeping the original spacing, for example `04xx xxx 123`.
  String get masked => maskNumber(text);
}

// ACMA geographic blocks: (0X) 5550 xxxx and (0X) 7010 xxxx, X in 2 3 7 8.
const _geoAreas = ['2', '3', '7', '8'];
const _geoBlocks = ['5550', '7010'];

// ACMA mobile numbers, as 0491 57 + the last four digits. The page lists
// these 30 numbers one by one; it is not a range.
const _mobilePrefix = '049157';
const _mobileSuffixes = [
  '0006', '0156', '0157', '0158', '0159', '0110', '0313', '0737', //
  '1266', '1491', '1804', //
  '2549', '2665', '2983', //
  '3770', '3087', //
  '4118', '4632', //
  '5254', '5789', //
  '6398', '6801', //
  '7426', '7644', //
  '8957', '8148', '8888', //
  '9212', '9760', '9455', //
];

// ACMA freephone and local rate numbers: 1800 160 401, 1800 975 707 to 711,
// 1300 975 707 to 711.
const _freeAndLocal = [
  ['1800', '160401'],
  ['1800', '975707'], ['1800', '975708'], ['1800', '975709'], //
  ['1800', '975710'], ['1800', '975711'], //
  ['1300', '975707'], ['1300', '975708'], ['1300', '975709'], //
  ['1300', '975710'], ['1300', '975711'], //
];

final Set<String> _fictional = {
  for (final a in _geoAreas)
    for (final b in _geoBlocks) '0$a$b', // prefix; any last four digits
  for (final s in _mobileSuffixes) '$_mobilePrefix$s',
  for (final p in _freeAndLocal) '${p[0]}${p[1]}',
};

/// Whether [national] (digits only, national form) is one of ACMA's
/// fictional numbers.
bool isAcmaFictional(String national) {
  if (RegExp(r'^0[2378]\d{8}$').hasMatch(national)) {
    return _fictional.contains(national.substring(0, 6));
  }
  return _fictional.contains(national);
}

// A separator between digits: nothing, or one space, dot or dash.
const _s = r'[ .\-]?';

// Not glued to a word, a `+`, or a digit run joined by `.` or `-` (versions,
// IDs, dates), on either side.
const _before = r'(?<![\w+]|\d[.\-])';
const _after = r'(?![\w]|[.\-]\d)';

final List<RegExp> _patterns = [
  // National mobile and geographic: 04xx xxx xxx, (02) xxxx xxxx, 0x.xxxx...
  RegExp('$_before\\(?0[2-478]\\)?(?:$_s\\d){8}$_after'),
  // E.164 and bare 61: +61 4xx xxx xxx, +61 (0)2 xxxx xxxx, 61 3..., and
  // +61 1300/1800 forms.
  RegExp('$_before\\+?61$_s(?:\\(0\\)$_s)?'
      '(?:[2-478](?:$_s\\d){8}|1[38]00(?:$_s\\d){6})$_after'),
  // 1300 xxx xxx and 1800 xxx xxx.
  RegExp('${_before}1[38]00(?:$_s\\d){6}$_after'),
  // 13 xx xx. Spaces only, so dates such as 13-05-26 are not read as numbers.
  RegExp('${_before}13(?: \\d\\d ?\\d\\d|\\d\\d \\d\\d)$_after'),
];

/// Every Australian phone number in [line], fictional or not.
List<PhoneHit> findAuPhoneNumbers(String line) {
  final hits = <PhoneHit>[];
  for (final p in _patterns) {
    for (final m in p.allMatches(line)) {
      if (hits.any((h) => m.start < h.end && h.start < m.end)) continue;
      final national = _national(m[0]!);
      final kind = _kind(national);
      if (kind == null) continue;
      hits.add(PhoneHit(
        start: m.start,
        end: m.end,
        text: m[0]!,
        national: national,
        kind: kind,
      ));
    }
  }
  hits.sort((a, b) => a.start.compareTo(b.start));
  return hits;
}

/// The Australian numbers in [line] that are not ACMA fictional numbers.
List<PhoneHit> findRealAuPhoneNumbers(String line) =>
    findAuPhoneNumbers(line).where((h) => !h.isFictional).toList();

String _national(String text) {
  final digits = text.replaceAll(RegExp(r'\D'), '');
  // No national form starts with 61, so a 61 start is always the E.164 form.
  if (!digits.startsWith('61')) return digits;
  var rest = digits.substring(2);
  if (text.contains('(0)')) rest = rest.substring(1);
  return rest.startsWith('1') ? rest : '0$rest';
}

AuNumberKind? _kind(String n) {
  if (RegExp(r'^04\d{8}$').hasMatch(n)) return AuNumberKind.mobile;
  if (RegExp(r'^0[2378]\d{8}$').hasMatch(n)) return AuNumberKind.geographic;
  if (RegExp(r'^1800\d{6}$').hasMatch(n)) return AuNumberKind.freephone;
  if (RegExp(r'^1300\d{6}$').hasMatch(n)) return AuNumberKind.localRate;
  if (RegExp(r'^13\d{4}$').hasMatch(n)) return AuNumberKind.localRateShort;
  return null;
}

/// [text] with its digits masked: the prefix (`04`, `02`, `+614`, `1800`,
/// `13`) and the last three digits stay, the rest become `x`. Spacing and
/// brackets stay as written.
String maskNumber(String text) {
  final digits = text.replaceAll(RegExp(r'\D'), '');
  final int keepHead;
  if (digits.startsWith('61') && digits.length > 9) {
    keepHead = digits.length - 9 + 1; // 61, an optional 0, the next digit
  } else if (digits.startsWith('1') && digits.length == 10) {
    keepHead = 4;
  } else {
    keepHead = 2;
  }
  final keepTail = digits.length >= 10 ? 3 : 2;
  final out = StringBuffer();
  var i = 0;
  for (final c in text.split('')) {
    if (RegExp(r'\d').hasMatch(c)) {
      out.write(i < keepHead || i >= digits.length - keepTail ? c : 'x');
      i++;
    } else {
      out.write(c);
    }
  }
  return out.toString();
}
