/// Australian numbers as people read them, and the small text helpers the
/// call screens share.
library;

/// Digits only (a leading + kept), for matching and dialling.
String dialDigits(String s) {
  final plus = s.trim().startsWith('+');
  final d = s.replaceAll(RegExp(r'[^0-9]'), '');
  return plus ? '+$d' : d;
}

/// The national form: +61355501987 to 0355501987; anything else unchanged.
String nationalDigits(String s) {
  final d = dialDigits(s);
  if (d.startsWith('+61')) return '0${d.substring(3)}';
  if (d.startsWith('61') && d.length == 11) return '0${d.substring(2)}';
  return d.replaceAll('+', '');
}

/// `03 5550 1987`, `0491 570 737`, `1300 975 707`, `13 1234`; extensions,
/// short numbers (000) and part-typed numbers as their digits.
String formatAuNumber(String raw) {
  if (raw == 'anonymous') return 'Private';
  final d = nationalDigits(raw);
  if (d.isEmpty) return raw;
  if (d.length <= 4 && !d.startsWith('0')) return d; // extension
  String group(String s, List<int> sizes) {
    final out = <String>[];
    var i = 0;
    for (final n in sizes) {
      if (i >= s.length) break;
      out.add(s.substring(i, (i + n).clamp(0, s.length)));
      i += n;
    }
    if (i < s.length) out[out.length - 1] += s.substring(i);
    return out.join(' ');
  }

  // Only a complete number is spaced: 000, 112 and part-typed numbers show
  // their digits as they are.
  if (d.length == 10 &&
      (d.startsWith('04') || d.startsWith('1300') || d.startsWith('1800'))) {
    return group(d, [4, 3, 3]);
  }
  if (d.length == 6 && d.startsWith('13')) return group(d, [2, 4]);
  if (d.length == 10 && d.startsWith('0')) return group(d, [2, 4, 4]);
  return d;
}

/// `2nd`, `3rd`, `11th`.
String ordinal(int n) {
  final t = n % 100;
  if (t >= 11 && t <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `2:02 pm`.
String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

/// `2:02 pm` today, `Tue 10:14 am` within the week, `14 Oct` before that.
String whenShort(DateTime at, DateTime now) {
  final a = at.toLocal(), n = now.toLocal();
  final day = DateTime(a.year, a.month, a.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return clockTime(a);
  if (diff > 0 && diff < 7) return '${_days[a.weekday - 1]} ${clockTime(a)}';
  return '${a.day} ${_months[a.month - 1]}';
}

/// `01:24`, `1:02:03` past the hour.
String callTimer(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// `JP` for Jordan Price, `W` for Westgate.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = [for (final w in words) w.characters.first];
  if (letters.isEmpty) return '';
  return (letters.length == 1 ? letters.first : letters.first + letters.last)
      .toUpperCase();
}

extension on String {
  Iterable<String> get characters sync* {
    for (final r in runes) {
      yield String.fromCharCode(r);
    }
  }
}
