import 'dart:io';

import 'package:call_engine/call_engine.dart';
import 'package:test/test.dart';

import 'support/test_numbers.dart';

/// Every way 000, 112 and 106 are written, with [n] the three digits.
List<String> writtenForms(String n) {
  final spaced = n.split('').join(' ');
  final plain = [
    n,
    spaced,
    '($n)',
    '$n#',
    '*$n',
    '+$n',
    // A trunk 0.
    '0$n',
    '0 $n',
    '(0) $n',
    // The country code.
    '+61 $n',
    '+61$n',
    '+61 $spaced',
    '61 $n',
    '61$n',
    '+61-$n',
    '(+61) $n',
    // The country code and a trunk 0.
    '+61 0 $n',
    '+61 (0) $n',
    '+61 (0)$n',
    '+610$n',
    '610$n',
    '61 0 $n',
    '61 (0) $n',
    // An international prefix in front of 61.
    '0061 $n',
    '0061$n',
    '00 61 $n',
    '+0061 $n',
    '0061 0 $n',
    '0061 (0) $n',
    '0011 61 $n',
    '001161$n',
    '0011 61 0 $n',
    '0011 61 (0) $n',
    '+0011 61 $n',
  ];
  // A caller-ID prefix in front of the usual forms.
  final hidden = [
    for (final p in ['1831 ', '1832 ', '1831', '#31#', '*31#', '#31# '])
      for (final f in [
        n,
        '0$n',
        '+61 $n',
        '61 $n',
        '0061 $n',
        '0011 61 $n',
        '+61 (0) $n',
      ])
        '$p$f',
  ];
  return [...plain, ...hidden];
}

/// "+61 00" and the like: after an international 61, a leftover 00 is 000
/// (TJ). All of them dial 000.
const zeroZeroForms = [
  '+61 00',
  '+6100',
  '+61 0 0',
  '+61 (0) 0',
  '(+61) 00',
  '0061 00',
  '006100',
  '00 61 00',
  '0011 61 00',
  '00116100',
  '+0011 61 00',
  '1831 +61 00',
  '#31# 0011 61 00',
];

/// Spaces and invisible characters, in front of and inside forms: only the
/// digits and + * # count, in Dart and in Kotlin alike (WS6 on #47). BOM,
/// next line, no-break space and zero-width space.
const separators = ['﻿', '\u0085', ' ', '​'];

/// Forms with [separators] in them, and the number each dials.
List<(String, String)> separatedForms() => [
  for (final s in separators) ...[
    ('${s}000', '000'),
    ('$s 112', '112'),
    ('${s}1831 000', '000'),
    ('1831${s}000', '000'),
    ('1${s}8${s}3${s}2 106', '106'),
    ('#31#${s}106', '106'),
    ('$s#31#000', '000'),
    ('$s+61 112', '112'),
    ('+61${s}112', '112'),
    ('0${s}0${s}0', '000'),
    ('0011${s}61${s}00', '000'),
    ('$s+61 00', '000'),
  ],
];

/// Near misses with [separators] in them.
List<String> separatedNearMisses() => [
  for (final s in separators) ...[
    '${s}1833 000',
    '61${s}00',
    '1831${s}0001',
    '0${s}0${s}0${s}1',
  ],
];

/// Caller-ID prefixes one after another: every leading one is dropped (TJ),
/// and the number each dials.
const repeatedPrefixForms = [
  ('1831 1831 000', '000'),
  ('#31#*31#000', '000'),
  ('1832 1831 112', '112'),
  ('*31#*31#106', '106'),
  ('1831 1832 1831 000', '000'),
  ('#31# #31# #31# 112', '112'),
  ('#31#1832 000', '000'),
  ('1832#31#106', '106'),
  ('*31#1831#31#1832 112', '112'),
  ('1831 1831 +61 00', '000'),
  ('#31#1832 +61 00', '000'),
  ('1832 1832 0011 61 00', '000'),
  ('1831 1831 0061 112', '112'),
  ('#31#*31# +61 (0) 106', '106'),
];

/// Not emergency numbers. In the shared table too, except the 13 number,
/// which stays in the files the phone number check allows it in.
const nearMisses = [
  '',
  '0',
  '00',
  '0001',
  '0006',
  '1120',
  '1122',
  '1060',
  '1061',
  '10612',
  '00000',
  '00 000',
  '000 000',
  '0000 0',
  '00112',
  '01120',
  // The country code with the wrong number after it, or extra digits.
  '61',
  '+61',
  '0061',
  '0011 61',
  '6100',
  '+61 0001',
  '+610001',
  '610001',
  '61 1120',
  '61 0 0 000',
  '+61 0 0000',
  '+61 61 000',
  '0061 61 000',
  '0011 61 61 000',
  '0011 0061 000',
  // A bare 61 00 (no +, 0061 or 0011 in front) stays a number.
  '61 00',
  '61 0 0',
  '1831 61 00',
  // A caller-ID prefix with nothing, or the wrong number, after it.
  '1831',
  '1832',
  '#31#',
  '*31#',
  '18310001',
  '1831 0001',
  '#31#0001',
  '1833 000',
  '1830 112',
  '#32#000',
  '1831 1833 000',
  '18311831',
  '1831 1832',
  '#31#*31#',
  '#31#1831',
  '1831 1831 0001',
  '#31#1833 112',
  '1831 1831 61 00',
  // An international prefix without 61, or 61 in the wrong place.
  '0011 000',
  '0011 112',
  '00 112',
  '000 61',
  '0 61 000',
  // Ordinary numbers, some with 000 or 112 inside.
  '0491 570 737',
  '0491 570 006',
  '+61 491 570 006',
  '03 5550 1201',
  '03 5550 0001',
  '+61 3 5550 1000',
  '0011 61 3 5550 1200',
  '*97',
  'sos',
];

void main() {
  // The Kotlin backstop (Rules.isEmergency) is tested on the shared table, so
  // the table has every form above.
  test('the shared table has every written form and every near miss', () {
    final lines = File('../vp_linphone/test/fixtures/emergency_numbers.txt')
        .readAsLinesSync();
    Set<String> rows(String kind) => {
      for (final l in lines)
        if (l.startsWith('$kind\t')) l.substring(2),
    };
    final emergency = rows('E'), not = rows('N');
    for (final typed in [
      for (final n in ['000', '112', '106']) ...writtenForms(n),
      ...zeroZeroForms,
      for (final (typed, _) in repeatedPrefixForms) typed,
      for (final (typed, _) in separatedForms()) typed,
    ]) {
      expect(emergency, contains(typed), reason: typed.runes.toString());
    }
    for (final typed in [...nearMisses, ...separatedNearMisses()]) {
      expect(not, contains(typed), reason: typed.runes.toString());
    }
  });

  group('emergencyNumberIn: every written form gives the three digits', () {
    for (final n in ['000', '112', '106']) {
      test(n, () {
        for (final typed in writtenForms(n)) {
          expect(emergencyNumberIn(typed), n, reason: typed);
          expect(isEmergencyNumber(typed), isTrue, reason: typed);
        }
      });
    }
  });

  test('every leading caller-ID prefix is dropped, not just one', () {
    for (final (typed, want) in repeatedPrefixForms) {
      expect(emergencyNumberIn(typed), want, reason: typed);
    }
  });

  test('after +61, 0061 or 0011 61, a leftover 00 is 000', () {
    for (final typed in zeroZeroForms) {
      expect(emergencyNumberIn(typed), '000', reason: typed);
    }
  });

  test('61 written together with the number is the country code (TJ)', () {
    for (final (typed, want) in [
      ('61000', '000'),
      ('61112', '112'),
      ('61106', '106'),
      ('610000', '000'),
      ('610112', '112'),
      ('610106', '106'),
    ]) {
      expect(emergencyNumberIn(typed), want, reason: typed);
    }
  });

  test('the forms the rule always had still match', () {
    for (final (typed, want) in [
      ('000', '000'),
      ('112', '112'),
      ('106', '106'),
      ('0000', '000'),
      ('0112', '112'),
      ('0106', '106'),
      ('0 0 0', '000'),
      ('(000)', '000'),
      ('112#', '112'),
      ('+112', '112'),
    ]) {
      expect(emergencyNumberIn(typed), want, reason: typed);
    }
  });

  test('spaces and invisible characters never hide one', () {
    for (final (typed, want) in separatedForms()) {
      expect(emergencyNumberIn(typed), want, reason: typed.runes.toString());
    }
    for (final typed in separatedNearMisses()) {
      expect(emergencyNumberIn(typed), isNull, reason: typed.runes.toString());
    }
  });

  test('leaves other numbers alone', () {
    for (final n in [...nearMisses, arbitrary13Number]) {
      expect(emergencyNumberIn(n), isNull, reason: n);
      expect(isEmergencyNumber(n), isFalse, reason: n);
    }
  });
}
